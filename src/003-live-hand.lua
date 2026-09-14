--------------------------------------------------------------------------------
-- 003-live-hand.lua
--
-- Sends one GM command to a RUNNING worldserver and returns what the console
-- printed back.
--
-- This rides on AzerothCore's built-in SOAP listener, which the deployment turns
-- on and pins to loopback (see its config/patches/C021-soap-loopback-console.sh).
-- neuron consumes that decision: it does not enable SOAP, does not edit the
-- deployment's config, and does not assume the endpoint is there. It probes, and
-- says clearly when the answer is "the world is up but SOAP is switched off",
-- because that is a thirty-second fix for anyone who is told it is the problem.
--
-- THE LIMIT THAT SHAPES THE WHOLE PROJECT:
--
--   A large part of the GM vocabulary acts on the *currently selected unit*.
--   A SOAP caller has no selection and cannot acquire one. Commands that take
--   an explicit character name are usable here; commands that only act on a
--   selection are not usable through this hand AT ALL.
--
--   That single constraint is why the cold hand exists. Where no name-taking
--   command exists for something, the database is the only route to it.
--
-- See issues/103-the-live-hand-soap.md for the blueprint.
--------------------------------------------------------------------------------

local LiveHand = {}

-- {{{ shell_quote(text)
-- Single-quote a value for use as one shell argument. See the identical note in
-- 002-cold-hand.lua: single quotes are total in POSIX shells, and the only
-- character needing care is the quote itself.
local function shell_quote(text)
    return "'" .. tostring(text):gsub("'", "'\\''") .. "'"
end
-- }}}

-- {{{ xml_escape(text)
-- Escape a command string for embedding in the SOAP envelope.
--
-- This is not decorative. A GM command carrying a character name with an
-- ampersand in it -- or a narration line with a quote -- produces malformed XML
-- that the worldserver rejects with a parse error rather than a useful message.
-- Escaping at the boundary means callers never have to think about it.
local function xml_escape(text)
    return (tostring(text)
        :gsub("&",  "&amp;")
        :gsub("<",  "&lt;")
        :gsub(">",  "&gt;")
        :gsub('"',  "&quot;")
        :gsub("'",  "&apos;"))
end
-- }}}

-- {{{ xml_unescape(text)
-- Reverse of the above, for reading console output back.
--
-- Ampersand is undone LAST. Undoing it first would turn "&amp;lt;" into "&lt;"
-- and then into "<", inventing a character the server never sent.
local function xml_unescape(text)
    return (tostring(text)
        :gsub("&lt;",   "<")
        :gsub("&gt;",   ">")
        :gsub("&quot;", '"')
        :gsub("&apos;", "'")
        :gsub("&#(%d+);", function(code) return string.char(tonumber(code)) end)
        :gsub("&amp;",  "&"))
end
-- }}}

-- {{{ build_envelope(command)
-- Wrap one command string in the SOAP envelope AzerothCore's listener expects.
--
-- The command text is what a GM would type after the dot, WITHOUT the dot:
-- "tele name Grast ratchet", never ".tele name Grast ratchet". The server adds
-- nothing and strips nothing; a leading dot arrives as part of the command name
-- and fails to match anything.
local function build_envelope(command)
    return table.concat({
        '<?xml version="1.0" encoding="utf-8"?>',
        '<SOAP-ENV:Envelope',
        ' xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/"',
        ' xmlns:xsd="http://www.w3.org/2001/XMLSchema"',
        ' xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"',
        ' xmlns:ns1="urn:AC">',
        '<SOAP-ENV:Body>',
        '<ns1:executeCommand>',
        '<command>', xml_escape(command), '</command>',
        '</ns1:executeCommand>',
        '</SOAP-ENV:Body>',
        '</SOAP-ENV:Envelope>',
    })
end
-- }}}

-- {{{ post(handle, body, timeout)
-- POST the envelope with HTTP Basic auth and return status plus body.
--
-- curl is the transport because LuaJIT ships no HTTP client and this project
-- takes no package-manager dependencies. The same choice will be made again in
-- phase 8 for the Claude API, deliberately, so the project has one HTTP path
-- rather than two.
--
-- --write-out appends the status code on its own final line, which is how the
-- status is recovered without a second request. -s silences the progress meter;
-- --show-error keeps real transport failures visible, because a silent curl
-- that failed looks exactly like a server that returned nothing.
local function post(handle, body, timeout)
    local Keys = dofile(handle.neuron_root .. "/src/052-keys.lua")

    -- Read at the point of use and let go again. The credential exists in this
    -- function and nowhere else -- not in the handle, not in a config table,
    -- not in an environment variable.
    local credential, why = Keys.read(handle.soap_key_path, "the SOAP key")
    if not credential then
        return nil, nil, why
    end

    -- The credential goes in a curl config file, not on the command line.
    --
    -- It used to be `--user account:password`, which is visible in `ps` output
    -- to every user on the machine for as long as the request runs. That is the
    -- exact hole a key file exists to close, and passing the key correctly all
    -- the way to the last step and then putting it in an argument list would
    -- close nothing.
    local config_path = string.format("%s/tmp/shared-memory/soap-%d-%d.conf",
        handle.neuron_root, os.time(), math.random(100000, 999999))

    local config_file = io.open(config_path, "w")
    if not config_file then
        return nil, nil, string.format(
            "cannot write a curl config at %s\n"
         .. "  Without it the credential would have to go on the command line,\n"
         .. "  where every user on this machine can read it, so this refuses\n"
         .. "  rather than falling back.\n"
         .. "  The RAM tier may be missing -- it is empty after every reboot and\n"
         .. "  the run scripts recreate it.", config_path)
    end

    config_file:write(string.format('user = "%s:%s"\n',
        handle.soap_account, credential))
    config_file:close()
    os.execute("chmod 600 " .. shell_quote(config_path))

    local command = table.concat({
        "curl",
        "-s", "--show-error",
        "--max-time", tostring(timeout or handle.probe_timeout or 3),
        "--basic", "--config", shell_quote(config_path),
        "-H", shell_quote("Content-Type: application/xml"),
        "--data-binary", shell_quote(body),
        "--write-out", shell_quote("\n%{http_code}"),
        shell_quote(handle.soap_url),
        "2>&1",
    }, " ")

    local pipe = io.popen(command, "r")
    if not pipe then
        os.remove(config_path)
        return nil, nil, "could not start curl"
    end
    local output = pipe:read("*a")
    local ok, _, code = pipe:close()

    -- Gone before anything is decided about the result, so that no early return
    -- below can leave a credential in the RAM tier outliving the process.
    os.remove(config_path)

    if not ok then
        -- curl's own exit codes distinguish the failures that matter here:
        -- 7 is "connection refused" (nothing listening -- world down, or SOAP
        -- disabled), 28 is a timeout (something is listening but wedged).
        local reason = "curl exited " .. tostring(code)
        if code == 7 then
            reason = "connection refused -- nothing is listening at " .. handle.soap_url
        elseif code == 28 then
            reason = "timed out after " .. tostring(timeout or handle.probe_timeout)
                  .. "s -- something is listening but did not answer"
        end
        return nil, nil, reason
    end

    -- The status code is the last line; everything before it is the body.
    local body_text, status = output:match("^(.*)\n(%d+)%s*$")
    if not status then
        return nil, nil, "could not read an HTTP status from curl output:\n" .. output
    end

    return tonumber(status), body_text, nil
end
-- }}}

-- {{{ extract_result(body)
-- Pull the console text out of a SOAP response body.
--
-- Two shapes come back and they mean opposite things:
--   <result>...</result>       the command ran; this is what the console printed
--   <faultstring>...</faultstring>  the command was rejected; this is why
--
-- A body with neither is a response this code does not understand, which is
-- reported as such rather than being flattened into an empty success.
local function extract_result(body)
    local result = body:match("<result>(.-)</result>")
    if result then
        return xml_unescape(result), nil
    end

    local fault = body:match("<faultstring>(.-)</faultstring>")
    if fault then
        return nil, xml_unescape(fault)
    end

    return nil, "unrecognised SOAP response:\n" .. body
end
-- }}}

-- {{{ LiveHand.execute(handle, command, timeout)
-- Run one GM command. Returns the console output, or nil plus a reason.
--
-- Note what "failure" means here. A GM command that the server rejects usually
-- returns HTTP 200 with an error sentence in the body -- NOT an HTTP error
-- code. So detecting failure means reading the body, and a caller that only
-- checks the status will believe every command succeeded.
function LiveHand.execute(handle, command, timeout)
    local status, body, why = post(handle, build_envelope(command), timeout)

    if not status then
        return nil, why
    end

    if status == 401 then
        return nil, "SOAP rejected the credentials (401) -- account '"
                 .. tostring(handle.soap_account) .. "' or its password is wrong"
    end

    if status ~= 200 and status ~= 500 then
        -- 500 is normal here: gSOAP returns a fault with status 500, and the
        -- fault text is the useful part, so it is read rather than discarded.
        return nil, "SOAP answered HTTP " .. status .. ":\n" .. tostring(body)
    end

    local result, fault = extract_result(body)
    if fault then
        return nil, fault
    end

    return result
end
-- }}}

-- {{{ LiveHand.probe(handle)
-- Is a worldserver reachable through SOAP, and if not, why not?
--
-- Four distinguishable outcomes with four different fixes:
--
--   no_credentials      no usable key at the configured soap_key path
--   connection_refused  world down, OR SOAP disabled in its config
--   soap_unauthorized   wrong account or password
--   up                  answered a harmless command
--
-- The probe command is `server info`, which reads and changes nothing. A probe
-- that altered state would make merely asking "is it up?" a side effect.
function LiveHand.probe(handle)
    -- Asked without ever holding the credential: `present` reads the file,
    -- checks it, and returns only whether it was usable.
    local Keys = dofile(handle.neuron_root .. "/src/052-keys.lua")

    local have, why = Keys.present(handle.soap_key_path, "the SOAP key")
    if not have then
        return false, "no_credentials", why
    end

    local result, why = LiveHand.execute(handle, "server info")

    if result then
        return true, "up", result
    end

    if why:find("401") or why:find("credentials") then
        return false, "soap_unauthorized", why
    end

    if why:find("refused") then
        return false, "connection_refused",
            why .. " -- either the worldserver is not running, or SOAP is "
                .. "disabled in its worldserver.conf"
    end

    return false, "unreachable", why
end
-- }}}

-- {{{ COMMANDS
-- The GM commands neuron actually uses, and how each one is addressed.
--
-- `addressing` is the field that matters, and it encodes the constraint at the
-- top of this file:
--
--   "name"      takes an explicit character name  -> usable over SOAP
--   "selection" acts on the GM's selected unit    -> NOT usable over SOAP
--   "none"      takes neither                     -> usable over SOAP
--
-- An operation declaring a live step is checked against this table when it
-- registers, so "this command cannot work without a selection" is caught at
-- startup rather than in front of a player.
--
-- This list grows deliberately, one entry at a time, as operations need them.
-- Transcribing AzerothCore's whole command surface would produce a large
-- document that is mostly wrong within a year and trusted anyway.
LiveHand.COMMANDS = {
    ["server info"]        = { addressing = "none",
                               summary = "version and uptime; used as the liveness probe" },
    ["tele name"]          = { addressing = "name",
                               summary = "teleport a named character to a named tele location" },
    ["appear"]             = { addressing = "name",
                               summary = "teleport yourself to a named character" },
    ["summon"]             = { addressing = "name",
                               summary = "teleport a named character to you" },
    ["gobject add"]        = { addressing = "selection",
                               summary = "spawn a gameobject at the GM's own position -- "
                                      .. "needs a body in the world, so phase 6 places "
                                      .. "props through the cold hand instead" },
    ["character level"]    = { addressing = "name",
                               summary = "set a named character's level" },
    ["send items"]         = { addressing = "name",
                               summary = "mail items to a named character" },
    ["announce"]           = { addressing = "none",
                               summary = "say something to every player online" },
    ["reload"]             = { addressing = "none",
                               summary = "reload a server table or the Lua corpus" },
}
-- }}}

-- {{{ LiveHand.addressing_of(command)
-- Look up how a command is addressed, by longest matching prefix.
--
-- Longest-prefix rather than exact match because callers pass complete command
-- lines ("tele name Grast ratchet"), and the table is keyed by the command
-- itself. An unknown command returns nil, which registration treats as "do not
-- allow this as a live step until somebody writes down how it is addressed".
function LiveHand.addressing_of(command)
    local best, best_length = nil, 0
    for prefix, entry in pairs(LiveHand.COMMANDS) do
        if command:sub(1, #prefix) == prefix and #prefix > best_length then
            best, best_length = entry.addressing, #prefix
        end
    end
    return best
end
-- }}}

return LiveHand
