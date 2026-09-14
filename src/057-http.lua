--------------------------------------------------------------------------------
-- 057-http.lua
--
-- Reading a request and writing a response. The plumbing under every page
-- neuron serves.
--
-- Extracted from the per-port chat server when a second server needed it, and
-- outlived it. Two copies
-- of a request parser is two parsers that drift, and the one thing they would
-- drift about is the query-string handling below -- which was already got wrong
-- once and is the sort of thing you fix in one place and forget about in the
-- other.
--
-- Deliberately small. This is enough HTTP for a browser tab on loopback talking
-- to a program on the same machine, and no more: no keep-alive, no chunked
-- bodies, no compression, no ranges. Each of those is real work in service of a
-- case nothing here can produce.
--------------------------------------------------------------------------------

local Http = {}

-- {{{ Http.MIME
Http.MIME = {
    html = "text/html; charset=utf-8",
    json = "application/json; charset=utf-8",
    txt  = "text/plain; charset=utf-8",
    css  = "text/css; charset=utf-8",
    js   = "application/javascript; charset=utf-8",
}
-- }}}

-- {{{ REASONS
local REASONS = {
    [200] = "OK",
    [400] = "Bad Request",
    [404] = "Not Found",
    [405] = "Method Not Allowed",
    [500] = "Internal Server Error",
    [503] = "Service Unavailable",
}
-- }}}

-- {{{ Http.respond(client, status, body, content_type)
-- Write one response and close.
--
-- Connection: close on every response, deliberately. Keep-alive would mean
-- tracking connection state for a server whose whole job is a handful of
-- requests from one browser tab, and the complexity buys nothing.
function Http.respond(client, status, body, content_type)
    client:send(table.concat({
        "HTTP/1.1 " .. status .. " " .. (REASONS[status] or "OK"),
        "Content-Type: " .. (content_type or Http.MIME.txt),
        "Content-Length: " .. #body,
        "Cache-Control: no-store",
        "Connection: close",
        "", body,
    }, "\r\n"))
    client:close()
end
-- }}}

-- {{{ Http.read_request(client)
-- The request line, the headers, and a body if one is promised.
--
-- Only Content-Length bodies are handled. Chunked encoding is not, and a
-- browser's fetch() with a string body never uses it -- so the missing case is
-- one nothing reaching these servers can produce.
function Http.read_request(client)
    client:settimeout(5)

    local line, why = client:receive("*l")
    if not line then
        return nil, "no request line: " .. tostring(why)
    end

    local method, target = line:match("^(%u+)%s+(%S+)%s+HTTP")
    if not method then
        return nil, "unparseable request line: " .. line
    end

    -- The request target carries the query string with it, so "/" and
    -- "/?ask=hello" arrive as different strings. Comparing the whole target
    -- against a route makes every parameterised link a 404, which is exactly
    -- what happened the first time one of these served a link.
    local path, query = target:match("^([^?]*)%??(.*)$")

    local headers = {}
    while true do
        local header = client:receive("*l")
        if not header or header == "" then break end
        local name, value = header:match("^([^:]+):%s*(.*)$")
        if name then headers[name:lower()] = value end
    end

    local body = ""
    local length = tonumber(headers["content-length"] or 0) or 0
    if length > 0 then
        body = client:receive(length) or ""
    end

    return { method = method, path = path, query = query,
             headers = headers, body = body }
end
-- }}}

-- {{{ Http.parameter(query, name)
-- One value out of a query string, percent-decoding it.
--
-- `+` becomes a space before the percent decoding, not after -- a literal plus
-- arrives as %2B, so decoding first would turn it into a space.
function Http.parameter(query, name)
    for pair in tostring(query or ""):gmatch("[^&]+") do
        local key, value = pair:match("^([^=]*)=?(.*)$")
        if key == name then
            value = value:gsub("+", " ")
            return (value:gsub("%%(%x%x)", function(hex)
                return string.char(tonumber(hex, 16))
            end))
        end
    end
    return nil
end
-- }}}

-- {{{ Http.lan_address()
-- This machine's address on its own network, or nil and why not.
--
-- Asked of the ROUTING TABLE rather than of the hostname. `hostname -I` prints
-- every address the machine has -- docker bridges, virtual interfaces, a second
-- NIC nobody uses -- in an order nothing guarantees, and picking the first is
-- how a page ends up advertised at 172.17.0.1 where no other machine can reach
-- it. `ip route get` asks the kernel which address it would actually SEND from,
-- which is the same address a machine on the network would answer to.
--
-- The destination is never contacted. This is a routing lookup, not a packet.
function Http.lan_address()
    local pipe = io.popen("ip route get 1.1.1.1 2>/dev/null", "r")
    if not pipe then
        return nil, "cannot run 'ip route get', so this machine's own address "
                 .. "on the network is unknown."
    end

    local answer = pipe:read("*a") or ""
    pipe:close()

    local address = answer:match("%ssrc%s+([%d%.]+)")

    if not address then
        return nil, "the routing table named no source address for an outside "
                 .. "destination, which usually means this machine has no "
                 .. "route off itself.\n  What 'ip route get 1.1.1.1' said:\n    "
                 .. (answer:gsub("\n", "\n    "))
    end

    return address
end
-- }}}

-- {{{ Http.listen(port, host)
-- A socket bound to `host`, which defaults to loopback.
--
-- THE DEFAULT IS 127.0.0.1 AND THAT IS NOT A PLACEHOLDER: these pages can empty
-- a world and they ask nobody who they are. There is no login, no key, no
-- session -- anybody who can open the page can pull every lever on it,
-- including the one that removes characters and cannot be undone.
--
-- Binding wider is therefore a decision somebody makes on purpose, by naming a
-- host, and it is worth naming what it means: on 0.0.0.0 every machine that can
-- route to this one gets the same unauthenticated front door. That is fine on a
-- home network you own and it is not fine anywhere else. The account-backed
-- login this needs is designed and not built.
function Http.listen(port, host)
    local socket = require("socket")

    host = host or "127.0.0.1"

    local server, why = socket.bind(host, port)
    if not server then
        return nil, string.format(
            "cannot listen on %s:%d\n  %s\n"
         .. "  Usually something else already has that port. To find out:\n"
         .. "      ss -lptn 'sport = :%d'\n"
         .. "  If the address is the problem rather than the port, %s is not an\n"
         .. "  address this machine holds -- 'ip -brief address' lists the ones\n"
         .. "  it does.", host, port, tostring(why), port, host)
    end

    server:settimeout(0.5)
    return server
end
-- }}}

return Http
