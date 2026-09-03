--------------------------------------------------------------------------------
-- 022-http-server.lua
--
-- A small HTTP server so the chat window has something to talk to.
--
-- Three routes and no framework: the page, the ask, and the apply. Built on
-- luasocket, which is already present on this machine, so nothing new is
-- installed and nothing is fetched at runtime.
--
-- BOUND TO LOOPBACK AND NOTHING ELSE, for the same reason the deployment binds
-- its game-master console there: this thing can empty a world and it
-- authenticates nobody. A door anyone on the network can open is a different
-- design with different requirements, and it is not this one.
--
-- THE PLAN/APPLY SPLIT REACHES ALL THE WAY UP. A request that would change
-- something comes back as a plan and is HELD here, keyed by an id. Confirming
-- runs the held plan rather than re-planning, so what gets applied is exactly
-- what was shown -- not a fresh computation that might differ.
--
-- See issues/901-the-browser-door.md for the blueprint.
--------------------------------------------------------------------------------

local socket = require("socket")

local HttpServer = {}

-- {{{ sibling(neuron_root, filename)
local function sibling(neuron_root, filename)
    return dofile(neuron_root .. "/src/" .. filename)
end
-- }}}

-- {{{ MIME
local MIME = {
    html = "text/html; charset=utf-8",
    json = "application/json; charset=utf-8",
    txt  = "text/plain; charset=utf-8",
}
-- }}}

-- {{{ respond(client, status, body, content_type)
-- Write one HTTP response and close.
--
-- Connection: close on every response, deliberately. Keep-alive would mean
-- tracking connection state for a server whose entire job is a handful of
-- requests from one browser tab, and the complexity buys nothing here.
local function respond(client, status, body, content_type)
    local reason = ({ [200] = "OK", [400] = "Bad Request",
                      [404] = "Not Found", [500] = "Internal Server Error" })[status] or "OK"
    client:send(table.concat({
        "HTTP/1.1 " .. status .. " " .. reason,
        "Content-Type: " .. (content_type or MIME.txt),
        "Content-Length: " .. #body,
        "Cache-Control: no-store",
        "Connection: close",
        "", body,
    }, "\r\n"))
    client:close()
end
-- }}}

-- {{{ read_request(client)
-- Read a request: the line, the headers, and a body if one is promised.
--
-- Only Content-Length bodies are handled. Chunked encoding is not, and a browser
-- fetch() with a string body never uses it -- so the missing case is one nothing
-- reaching this server can produce.
local function read_request(client)
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
    -- against a route makes every link with a parameter on it a 404, which is
    -- what happened the first time this served one.
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

-- {{{ HttpServer.new(handle, options)
-- Build a server. Nothing listens until run() is called.
function HttpServer.new(handle, options)
    options = options or {}

    return {
        handle   = handle,
        host     = "127.0.0.1",
        port     = options.port or 7879,
        -- Plans held between the ask and the confirm, keyed by id.
        --
        -- In memory and lost when the server stops, which is correct: a plan is
        -- a statement about the world at one moment, and one that outlived the
        -- process would be a statement about a world that may have moved on.
        plans    = {},
        sequence = 0,
    }
end
-- }}}

-- {{{ hold_plan(server, plan, operation)
-- Keep a computed plan so confirming runs exactly what was shown.
local function hold_plan(server, plan, operation)
    server.sequence = server.sequence + 1
    local id = "plan-" .. server.sequence
    server.plans[id] = { plan = plan, operation = operation, made = os.time() }
    return id
end
-- }}}

-- {{{ handle_ask(server, text)
-- Route a sentence, run it, and describe what happened.
--
-- Returns a table the page renders. Three shapes, and the page shows each
-- differently:
--
--   kind = "said"    plain output; nothing changed
--   kind = "plan"    something WOULD change; carries a plan id to confirm
--   kind = "trouble" it could not be done, and why
local function handle_ask(server, text)
    local neuron_root = server.handle.neuron_root

    local ChatRouter = sibling(neuron_root, "021-chat-router.lua")
    local Liveness   = sibling(neuron_root, "004-liveness.lua")

    local route = ChatRouter.route(text)

    if not route then
        -- Handed to a model. There isn't one configured, and saying so plainly
        -- -- with what WOULD have worked -- is the only thing standing between
        -- the person and guessing.
        local lines = {}
        for _, entry in ipairs(ChatRouter.vocabulary()) do
            table.insert(lines, entry.example)
        end
        return {
            kind = "trouble",
            text = "I don't understand that yet. Asking in free language needs a "
                .. "model, and none is configured (no ANTHROPIC_API_KEY).\n\n"
                .. "Things I do understand:",
            examples = lines,
        }
    end

    if route.op == "help" then
        local lines = {}
        for _, entry in ipairs(ChatRouter.vocabulary()) do
            table.insert(lines, string.format("%-32s %s", entry.example, entry.does))
        end
        return { kind = "said", text = table.concat(lines, "\n") }
    end

    local state = Liveness.probe(server.handle)

    local fault = Liveness.fault(state)
    if fault then
        return { kind = "trouble", text = fault }
    end

    -- Reads first. None of these change anything, so none of them hold a plan.
    if route.op == "status" then
        local Deployment = sibling(neuron_root, "000-deployment.lua")
        return { kind = "said", text = Deployment.describe(server.handle)
            .. "\n\n" .. Liveness.describe(state) }
    end

    if not state.db_up then
        return { kind = "trouble",
            text = "The database is not running, so I cannot see anything.\n"
                .. Liveness.describe(state) }
    end

    if route.op == "places" then
        local PlaceBook = sibling(neuron_root, "011-place-book.lua")
        local found, why = PlaceBook.search(server.handle, route.args.fragment, 20)
        if not found then return { kind = "trouble", text = why } end
        if #found == 0 then
            return { kind = "trouble",
                text = "No place matches '" .. route.args.fragment .. "'." }
        end
        local lines = {}
        for _, place in ipairs(found) do
            table.insert(lines, PlaceBook.describe(place))
        end
        return { kind = "said", text = table.concat(lines, "\n") }
    end

    if route.op == "who" then
        local Rosters   = sibling(neuron_root, "012-rosters.lua")
        local WorldRead = sibling(neuron_root, "005-world-read.lua")
        local resolution, why = Rosters.resolve(server.handle, route.args.roster, { limit = 40 })
        if not resolution then return { kind = "trouble", text = why } end
        -- The characters are returned as data rather than as rendered lines,
        -- so the page can colour each name by class the way the game does.
        -- Class colour is the one piece of formatting every WoW player already
        -- reads without thinking, and throwing it away to send a string would
        -- be discarding meaning the reader already has.
        local people = {}
        for _, character in ipairs(resolution.characters) do
            table.insert(people, {
                name  = character.name,
                level = character.level,
                race  = character.race_name or "?",
                class = character.class_name or "?",
                kind  = WorldRead.kind_of(character),
                online = character.online,
                where = WorldRead.MAPS[character.map] or ("map " .. tostring(character.map)),
            })
        end
        return { kind = "said", text = Rosters.describe(resolution), people = people }
    end

    if route.op == "check" then
        local Dangling = sibling(neuron_root, "016-dangling.lua")
        local result, why = Dangling.check(server.handle)
        if not result then return { kind = "trouble", text = why } end
        return { kind = result.total > 0 and "trouble" or "said",
                 text = Dangling.describe(result) }
    end

    if route.op == "receipts" then
        local Receipts = sibling(neuron_root, "006-receipts.lua")
        local found = Receipts.read(server.handle, {})
        if #found == 0 then
            return { kind = "said", text = "Nothing has been done today." }
        end
        local lines = {}
        for index = #found, math.max(1, #found - 9), -1 do
            table.insert(lines, Receipts.describe(found[index]))
            table.insert(lines, "")
        end
        return { kind = "said", text = table.concat(lines, "\n") }
    end

    -- Anything that changes the world is planned and HELD.
    if route.op == "teleport" then
        local Teleport = sibling(neuron_root, "013-teleport.lua")
        local plan, why = Teleport.plan(server.handle, route.args)
        if not plan then return { kind = "trouble", text = why } end
        return {
            kind    = "plan",
            text    = Teleport.describe_plan(plan),
            plan_id = hold_plan(server, plan, "teleport"),
        }
    end

    if route.op == "return" then
        local Return = sibling(neuron_root, "014-return.lua")
        local plan, why = Return.plan(server.handle, route.args)
        if not plan then return { kind = "trouble", text = why } end
        return {
            kind    = "plan",
            text    = Return.describe_plan(plan),
            plan_id = hold_plan(server, plan, "return"),
        }
    end

    return { kind = "trouble", text = "'" .. route.op .. "' has no door yet." }
end
-- }}}

-- {{{ handle_apply(server, plan_id)
-- Run a held plan.
--
-- The plan is REMOVED as it runs, whatever the outcome. A plan is a statement
-- about the world at one moment; once acted on, that moment is gone, and leaving
-- it available to run twice is how somebody teleports a party to the docks twice
-- and wonders why the second one did nothing.
local function handle_apply(server, plan_id)
    local held = server.plans[plan_id]
    if not held then
        return { kind = "trouble",
            text = "That plan is no longer available. Plans are held only until "
                .. "they run, and are lost if the server restarts. Ask again." }
    end
    server.plans[plan_id] = nil

    local neuron_root = server.handle.neuron_root
    local Liveness = sibling(neuron_root, "004-liveness.lua")
    local Receipts = sibling(neuron_root, "006-receipts.lua")

    local state = Liveness.probe(server.handle)

    local module = ({ teleport = "013-teleport.lua",
                      ["return"] = "014-return.lua" })[held.operation]
    local Operation = sibling(neuron_root, module)

    local receipt = Operation.apply(server.handle, held.plan, state)

    return {
        kind    = receipt.outcome == "complete" and "done" or "trouble",
        text    = Receipts.describe(receipt),
        outcome = receipt.outcome,
    }
end
-- }}}

-- {{{ read_page(neuron_root)
-- The chat window, read from disk each time.
--
-- Re-read per request rather than cached, so editing the page and refreshing the
-- browser shows the change without restarting the server. It is one small file
-- and this is a single-user loopback server; the cost is nothing and the
-- convenience is real.
local function read_page(neuron_root)
    local file = io.open(neuron_root .. "/assets/chat.html", "r")
    if not file then
        return nil
    end
    local page = file:read("*a")
    file:close()
    return page
end
-- }}}

-- {{{ HttpServer.run(server)
-- Listen, and serve until interrupted.
function HttpServer.run(server)
    local Json = sibling(server.handle.neuron_root, "001-json.lua")

    local listener, why = socket.bind(server.host, server.port)
    if not listener then
        return nil, string.format(
            "cannot listen on %s:%d -- %s\n  Another copy may already be running.",
            server.host, server.port, tostring(why))
    end
    listener:settimeout(0.5)

    print(string.format("neuron chat is open at http://%s:%d",
        server.host, server.port))
    print("bound to loopback only. ctrl-c to stop.")
    print("")

    while true do
        local client = listener:accept()
        if client then
            local request, request_why = read_request(client)

            if not request then
                respond(client, 400, tostring(request_why), MIME.txt)

            elseif request.method == "GET" and (request.path == "/" or request.path == "/index.html") then
                local page = read_page(server.handle.neuron_root)
                if page then
                    respond(client, 200, page, MIME.html)
                else
                    respond(client, 500, "assets/chat.html is missing", MIME.txt)
                end

            elseif request.method == "POST" and request.path == "/ask" then
                local asked = Json.decode(request.body) or {}
                -- pcall so a fault in one operation returns an error to the page
                -- instead of killing the server the page is talking to.
                local ok, result = pcall(handle_ask, server, asked.text)
                if not ok then
                    result = { kind = "trouble", text = "something broke:\n" .. tostring(result) }
                end
                respond(client, 200, Json.encode(result), MIME.json)

            elseif request.method == "POST" and request.path == "/apply" then
                local asked = Json.decode(request.body) or {}
                local ok, result = pcall(handle_apply, server, asked.plan_id)
                if not ok then
                    result = { kind = "trouble", text = "something broke:\n" .. tostring(result) }
                end
                respond(client, 200, Json.encode(result), MIME.json)

            else
                respond(client, 404, "no such thing here", MIME.txt)
            end
        end
    end
end
-- }}}

return HttpServer
