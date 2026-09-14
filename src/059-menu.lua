--------------------------------------------------------------------------------
-- 059-menu.lua
--
-- The front door. One page, one level above everything else.
--
-- Neuron grew from the inside out: the levers first, then a command line, then
-- a chat window, then a model behind it. Every one of those is reached by
-- knowing a script name and a flag, which is fine for whoever built it and
-- obtuse for anybody else -- including the person who built it, three weeks
-- later, at a machine that has just rebooted.
--
-- This is the page that assumes nothing. What is running, what is not, what to
-- press to change that, where the conversations are, and what words exist.
--
-- It is deliberately a DIFFERENT SERVER from the chat window rather than
-- another route on it. A chat window is one conversation and holds the plans of
-- that conversation; the menu is about the machine and must answer while
-- everything else is down -- including while no chat window exists at all.
--------------------------------------------------------------------------------

local Menu = {}

-- {{{ sibling(neuron_root, filename)
local function sibling(neuron_root, filename)
    return dofile(neuron_root .. "/src/" .. filename)
end
-- }}}

-- {{{ Menu.new(handle, port)
-- `host` is the address to bind. Loopback unless somebody names another --
-- see Http.listen for what binding wider means, which is: an unauthenticated
-- front door for every machine that can route here.
function Menu.new(handle, port, host)
    return { handle = handle, port = port or 7900, host = host or "127.0.0.1" }
end
-- }}}

-- {{{ world_summary(handle)
-- A few numbers about the world, or the reason there are none.
--
-- Wrapped in pcall because this is the one part of the menu that needs the
-- database, and the menu's whole value is answering when things are down. A
-- page that failed to load because the world was unreachable would be useless
-- at exactly the moment somebody opened it.
local function world_summary(handle)
    local ok, result = pcall(function()
        local WorldRead = sibling(handle.neuron_root, "005-world-read.lua")
        return WorldRead.summary(handle)
    end)

    if not ok or not result then
        return { readable = false,
                 why = "The database did not answer, so there is nothing to "
                    .. "count. That is what the mysql row above is for." }
    end

    return {
        readable    = true,
        players     = result.players_online or 0,
        bots_online = result.bots_online or 0,
        online      = result.online or 0,
    }
end
-- }}}

-- {{{ vocabulary(handle)
-- Every word neuron knows, for the page to list.
local function vocabulary(handle, which)
    local ok, registry = pcall(function()
        local Registry = sibling(handle.neuron_root, "045-toolbox/047-registry.lua")
        return (Registry.load(handle.neuron_root, which))
    end)

    if not ok or not registry then return {} end

    local words = {}
    for _, operation in ipairs(registry.ordered) do
        local hands, params = {}, {}
        for _, hand in ipairs(operation.hands) do table.insert(hands, hand.name) end
        for _, parameter in ipairs(operation.params) do
            table.insert(params, (parameter.required and "" or "[")
                .. parameter.name .. (parameter.required and "" or "]"))
        end

        table.insert(words, {
            name    = operation.name,
            glyph   = operation.kind.glyph,
            kind    = operation.kind.name,
            summary = operation.summary,
            hands   = table.concat(hands, " or "),
            params  = table.concat(params, " "),
            -- Why this word cannot be used here, or nil. A word is not hidden
            -- when a module is missing -- it is shown, in its own section, with
            -- the reason. "That word does not exist" and "that word needs
            -- something this server was not built with" are different answers
            -- and only one of them is actionable.
            unavailable = (function()
                local Addons = sibling(handle.neuron_root, "072-addons.lua")
                return Addons.why_missing(handle, operation.needs)
            end)(),
        })
    end

    return words
end
-- }}}

-- {{{ library(handle)
-- Every word, sorted by WHO CAN SAY IT.
--
-- Three groups, because there are three answers and the middle one is the
-- interesting one:
--
--   the local model alone -- configuring where thinking is sent, reading the
--   project, writing credentials. The life-raft vocabulary: what you need when
--   nothing works, available without reaching anything remote.
--
--   both -- managing the conversation itself. Nothing to do with the world or
--   with configuration; it is about the conversation having a size.
--
--   the remote model alone -- the world. Characters, creatures, places.
--
-- Built by comparing the two registries rather than by a hand-kept list, so a
-- word added to a vocabulary appears here without anybody remembering to say
-- so. A list somebody maintains is a list that is wrong the first time
-- somebody forgets.
local function library(handle)
    local asking = {}
    for _, word in ipairs(vocabulary(handle, "asking")) do
        asking[word.name] = word
    end

    local world = {}
    for _, word in ipairs(vocabulary(handle, "world")) do
        world[word.name] = word
    end

    local local_only, shared, remote_only, disabled = {}, {}, {}, {}

    for name, word in pairs(asking) do
        table.insert(world[name] and shared or local_only, word)
    end

    for name, word in pairs(world) do
        if not asking[name] then table.insert(remote_only, word) end
    end

    -- Anything a missing module has taken away, lifted out of whichever group
    -- it belongs to and gathered at the bottom. It is still listed -- knowing a
    -- word exists and why you cannot use it is the actionable answer -- but it
    -- is not mixed in with the ones that work.
    for _, group in ipairs({ local_only, shared, remote_only }) do
        for index = #group, 1, -1 do
            if group[index].unavailable then
                table.insert(disabled, table.remove(group, index))
            end
        end
    end

    for _, group in ipairs({ local_only, shared, remote_only, disabled }) do
        table.sort(group, function(a, b) return a.name < b.name end)
    end

    local Json = sibling(handle.neuron_root, "001-json.lua")

    local groups = {
        { title = "the configuration assistant, and only the assistant",
          what  = "Setting up how thinking gets sent somewhere, reading the "
               .. "project, and writing credentials. This is the life raft: it "
               .. "is what you still have when the game master cannot be "
               .. "reached, and it can change nothing in the world.",
          words = Json.array(local_only) },

        { title = "both of them",
          what  = "Managing the conversation itself rather than the world or "
               .. "the configuration. A conversation has a size, and this is "
               .. "what does something about that.",
          words = Json.array(shared) },

        { title = "the game master, and only the game master",
          what  = "The world. Characters, creatures, places -- everything that "
               .. "someone standing in the game would notice.",
          words = Json.array(remote_only) },
    }

    -- Only when there is something in it. A permanent empty heading reading
    -- "disabled because of a missing addon" tells somebody with a complete
    -- install about a problem they do not have.
    if #disabled > 0 then
        table.insert(groups, {
            title = "disabled, because of a missing addon",
            what  = "These exist and cannot be used on this deployment. Each "
                 .. "says what it is waiting for.",
            words = Json.array(disabled) })
    end

    return groups
end
-- }}}

-- {{{ keys(handle)
-- Which credentials are present, and the exact command for the ones that are
-- not.
--
-- On the menu because this is where somebody hits a wall. Both of them are
-- optional and neither absence is an error -- but "worldserver: down" with no
-- explanation, when the real answer is a missing file and one chmod, is the
-- obtuseness this page exists to remove.
local function keys(handle)
    local Keys = sibling(handle.neuron_root, "052-keys.lua")

    local listed = {}

    -- The PATH is what the row shows, so somebody who has to go and edit one
    -- can see where it is. Derived from the handle rather than written out
    -- here: neuron and its deployment can both move, and a path built by
    -- concatenation in the page would point at wherever they used to be.
    for _, entry in ipairs({
        { name = "soap.key",
          path = handle.soap_key_path,
          for_what = "for altering the world while the server is ONLINE",
          what = nil },
        { name = "api.key",
          path = handle.api_key_path,
          for_what = "for the game master",
          what = nil },
    }) do
        local present, why = Keys.present(entry.path, "the " .. entry.name)

        -- Same trap as the addon list: `present and nil or why` yields `why`
        -- whichever way `present` went, so a credential that was there arrived
        -- with an explanation of why it was not.
        local row = { name = entry.name, what = entry.what, path = entry.path,
                      for_what = entry.for_what, present = present }

        if not present then row.why = why end

        table.insert(listed, row)
    end

    return listed
end
-- }}}

-- {{{ receipts(handle, limit)
-- What was actually done to the world, newest first, with what can be undone
-- marked.
local function receipts(handle, limit)
    local ok, result = pcall(function()
        local Receipts = sibling(handle.neuron_root, "006-receipts.lua")
        return (Receipts.read(handle, {}))
    end)

    if not ok or not result then return {} end

    local listed = {}
    for index = #result, math.max(1, #result - (limit or 15) + 1), -1 do
        local receipt = result[index]
        table.insert(listed, {
            id        = receipt.id,
            operation = receipt.operation,
            outcome   = receipt.outcome,
            when      = os.date("%H:%M:%S", receipt.finished or receipt.started or 0),
            steps     = receipt.steps and #receipt.steps or 0,
            -- Only a move can be put back. A removal wrote down what it
            -- destroyed and cannot restore it, and offering a button that
            -- would fail is worse than offering none.
            undoable  = receipt.operation == "character.teleport",
        })
    end

    return listed
end
-- }}}

-- {{{ Menu.state(server)
-- Everything the page draws itself from, in one request.
--
-- One request rather than six, because six requests is six chances for the page
-- to be half-drawn, and a menu that is half-drawn about what is running is
-- worse than one that is slow.
-- `probe` decides whether this reaches OUT. Without it the answer is built
-- entirely from what the machine already knows -- which ports are held, what is
-- on disk -- and costs nothing.
--
-- The distinction matters at more than one person. A page that refreshed itself
-- meant every open browser asking every few seconds; five hundred of them would
-- be five hundred `ss` calls and five hundred requests at the local model, for a
-- set of facts that changes a few times a day. Now nothing happens until
-- somebody presses something.
-- `probe` names WHICH endpoint to reach for: "configured", "bench", "all", or
-- nil for none. One name rather than a flag, because the two checks are
-- separate questions with separate answers and separate buttons -- pressing
-- check beside the local model should not go anywhere near the remote one.
function Menu.state(server, probe)
    local ask_configured = probe == "all" or probe == "configured"
    local ask_bench      = probe == "all" or probe == "bench"

    local handle   = server.handle
    local Services = sibling(handle.neuron_root, "058-services.lua")
    local Json     = sibling(handle.neuron_root, "001-json.lua")

    -- EVERY list here is marked as a list. An unmarked empty one encodes as
    -- `{}`, the page calls .map on it, and the exception unwinds the whole
    -- render -- so a day with no conversations blanked the receipts, the world
    -- count and the vocabulary too. The marker costs nothing and the failure
    -- it prevents is silent and total.
    local services = Json.array()
    for _, service in ipairs(Services.of(handle)) do
        local state = Services.state(service)
        table.insert(services, {
            name     = service.name,
            what     = service.what,
            port     = service.port,
            up       = state.up,
            starting = state.starting or false,
            group    = state.group,
            profile_agnostic = service.profile_agnostic or false,
            runnable = service.runnable,
            why_not  = service.why_not,
            pid      = state.pid,
            log      = service.log,
            -- Is there anything to show? The captured output exists only for a
            -- server neuron started; one launched in a terminal has none, and
            -- showing the last run's file with nothing admitting it is worse
            -- than showing nothing. Where the server's own log can be located
            -- from its config, that is read instead.
            has_log  = (function()
                for _, path in ipairs({ service.log, service.server_log }) do
                    if path then
                        local file = io.open(path, "r")
                        if file then file:close() return true end
                    end
                end
                -- A named log file that does not exist yet is the same as no
                -- log: the config saying where one WOULD be written is not
                -- evidence that anything ever wrote it.
                return false
            end)(),
            stoppable = service.stop ~= nil,
            stop_why = service.stop_why,
            requires_down = service.requires_down,
            requires_up   = service.requires_up,
            console      = service.console,
            console_why  = service.console_why,
        })
    end

    return {
        deployment = handle.root,
        profile    = handle.profile,
        profiles   = (function()
            local defined = {}
            local file = io.open(handle.root .. "/scripts/profiles", "r")
            if not file then return Json.array() end
            local text = file:read("*a")
            file:close()
            local block = text:match("PROFILE_REPO=%b()")
            for name in (block or ""):gmatch('%["([%w_]+)%"%]') do
                table.insert(defined, name)
            end
            table.sort(defined)
            return Json.array(defined)
        end)(),
        overridden = handle.profile_overridden or false,
        services   = services,

        world      = world_summary(handle),
        -- Both models' settings, in the same shape, so one editor serves both.
        asking_targets = (function()
            local asking = handle.asking or {}

            -- {{{ pieces(url)
            local function pieces(url)
                url = url or ""
                return {
                    url    = url,
                    scheme = url:match("^(https?)://") or "http",
                    host   = url:match("^https?://([^:/]+)") or "",
                    port   = url:match("^https?://[^:/]+:(%d+)") or "",
                    path   = url:match("^https?://[^/]+(/.*)$") or "/",
                }
            end
            -- }}}

            local master = pieces(asking.url)
            master.model   = asking.model
            master.dialect = asking.dialect or "anthropic"
            master.timeout = asking.timeout_seconds or 120

            local assistant = asking.bench and pieces(asking.bench.url) or nil
            if assistant then
                assistant.model   = asking.bench.model
                assistant.dialect = asking.bench.dialect or "ollama"
                assistant.timeout = asking.bench.timeout_seconds or 300
            end

            return { configured = master, bench = assistant,
                     dialects = Json.array({ "anthropic", "ollama" }) }
        end)(),

        model      = (function()
            local ok, chosen = pcall(function()
                local Api = sibling(handle.neuron_root, "050-api.lua")
                if not ask_configured then
                    -- The configuration alone, with nothing reached for.
                    local asking = handle.asking or {}
                    return { which = asking.use == "bench" and "bench" or "configured",
                             model = asking.use == "bench"
                                 and (asking.bench and asking.bench.model)
                                 or asking.model,
                             url = asking.use == "bench"
                                 and (asking.bench and asking.bench.url)
                                 or asking.url,
                             usable = nil, unchecked = true }
                end
                -- Api.chosen answers from the configuration and the key
                -- file; with a key present it reaches nothing at all. So the
                -- check button beside this row has to ask the endpoint itself,
                -- or it is a button labelled "check" that checks nothing.
                --
                -- A HEAD request. It costs no tokens and no money -- which is
                -- the whole reason this can be a button somebody presses
                -- freely.
                local chosen = Api.chosen(handle)
                if chosen.url then
                    chosen.answering = Api.reachable(chosen.url, true)
                    chosen.checked   = true
                    chosen.unchecked = nil
                end
                return chosen
            end)
            return ok and chosen or { which = "none", usable = false,
                why = "The asking configuration could not be read." }
        end)(),
        keys          = Json.array(keys(handle)),

        -- {{{ the deployment, and where every value came from
        -- Each row says whether neuron worked a value out or was told it.
        -- "detected" and "you set this" are different claims, and the standing
        -- position that a fallback is a warning has nothing to stand on unless
        -- the page can tell them apart at a glance.
        deployment_facts = (function()
            local ServerConfig = sibling(handle.neuron_root, "073-server-config.lua")

            local world = ServerConfig.read(handle.config_dir .. "/worldserver.conf")
            local auth  = ServerConfig.read(handle.config_dir .. "/authserver.conf")

            -- {{{ standing(path, kind)
            -- Green if it is there, red if it is not, amber if it is there and
            -- unusable. Three answers, because "the file exists" and "the file
            -- is what it claims to be" are different questions and only the
            -- second one means the setting works.
            local function standing(path, kind)
                if not path or path == "" then return "missing" end

                if kind == "dir" then
                    local Overrides = sibling(handle.neuron_root,
                                              "074-overrides.lua")
                    return Overrides.readable_dir(path) and "good" or "missing"
                end

                if kind == "program" then
                    local Overrides = sibling(handle.neuron_root,
                                              "074-overrides.lua")
                    return Overrides.executable(path) and "good" or "missing"
                end

                local file = io.open(path, "r")
                if not file then return "missing" end

                -- A config file that opens and says nothing neuron needs is
                -- the amber case: present, and not the file it is meant to be.
                if kind == "config" then
                    local text = file:read(200000) or ""
                    file:close()
                    return text:find("DatabaseInfo", 1, true) and "good"
                                                              or "malformed"
                end

                file:close()
                return "good"
            end
            -- }}}

            return {
                root         = handle.root,
                root_state   = standing(handle.root, "dir"),
                config_dir   = handle.config_dir,
                config_where = handle.config_detected and "detected"
                                                      or "you set this",
                -- Named individually, with full paths. "its configuration"
                -- said nothing about WHICH files, and a directory shown where
                -- two files are meant reads as one thing when it is two --
                -- they can be moved apart, and each is separately settable.
                --
                -- The directory is still searched behind the scenes; that is
                -- how they are found. It is simply not what is shown, because
                -- a path to a directory is not a path to a file.
                config_files = Json.array({
                    (function()
                        local path = (handle.overrides or {}).worldserver_conf
                            or (handle.config_dir .. "/worldserver.conf")
                        return { name = "worldserver.conf", path = path,
                          key  = "worldserver_conf",
                          set  = (handle.overrides or {}).worldserver_conf ~= nil,
                          state = standing(path, "config"),
                        }
                    end)(),
                    (function()
                        local path = (handle.overrides or {}).authserver_conf
                            or (handle.config_dir .. "/authserver.conf")
                        return { name = "authserver.conf", path = path,
                          key  = "authserver_conf",
                          set  = (handle.overrides or {}).authserver_conf ~= nil,
                          state = standing(path, "config"),
                        }
                    end)(),
                }),
                profile      = handle.profile,
                has_profiles = handle.profile ~= nil,
                mysql_client = handle.mysql_binary,
                mysql_client_state = standing(handle.mysql_binary, "program"),
                mysql_client_set = (handle.overrides or {}).mysql_client ~= nil,
                soap_account = handle.soap_account,
                soap_key_present = (function()
                    local Keys = sibling(handle.neuron_root, "052-keys.lua")
                    return (Keys.present(handle.soap_key_path, "the soap key"))
                end)(),
            }
        end)(),
        -- }}}
        bench         = (function()
            local asking = handle.asking
            if not asking or not asking.bench then return nil end
            local Api = sibling(handle.neuron_root, "050-api.lua")
            return { model = asking.bench.model, url = asking.bench.url,
                     host = asking.bench.url:match("^https?://([^:/]+)"),
                     port = asking.bench.url:match("^https?://[^:/]+:(%d+)"),
                     path = asking.bench.url:match("^https?://[^/]+(/.*)$"),
                     -- Only when asked. This is a request over the network.
                     reachable = ask_bench
                         and Api.reachable(asking.bench.url, true) or nil,
                     checked = ask_bench }
        end)(),
        conversations = (function()
            local Transcript = sibling(handle.neuron_root, "067-transcript.lua")
            local ok, listed = pcall(Transcript.list, handle, 60)
            return Json.array(ok and listed or {})
        end)(),
        receipts      = Json.array(receipts(handle)),
        -- The vocabulary is NOT here any more. It is a page of reference that
        -- changes when the code changes and never otherwise, and it was sitting
        -- under the things somebody opens this page to act on. It lives at
        -- /library now, fetched when asked for.
        library_size  = (function()
            local total = 0
            for _, group in ipairs(library(handle)) do
                total = total + #group.words
            end
            return total
        end)(),
    }
end
-- }}}

-- {{{ find_service(handle, name)
local function find_service(handle, name)
    local Services = sibling(handle.neuron_root, "058-services.lua")
    for _, service in ipairs(Services.of(handle)) do
        if service.name == name then return service, Services end
    end
    return nil
end
-- }}}

-- {{{ Menu.act(server, what, name)
-- Start or stop something, and say what happened in words.
function Menu.act(server, what, name)
    local handle = server.handle

    -- `admin`, `chat` and `close` used to live here. They started and stopped
    -- a chat window as its own process on its own port, by running
    -- scripts/start-chat and scripts/stop-chat -- neither of which exists any
    -- more. Conversations are transcripts served by this menu now, opened
    -- through /conversation/new, and the page's buttons have gone there for a
    -- while. A call to a script that is not there is worse than no call: it
    -- fails silently and reports success.
    --
    -- Their removal took the line that resolved the service with them: it sat
    -- inside the `close` branch, which was the last of the three, and the two
    -- branches below had been reading the variable it left behind.
    local service, Services = find_service(handle, name)

    if not service then
        return { ok = false, text = string.format(
            "There is no service called '%s'.", tostring(name)) }
    end

    if what == "start" then
        -- Refuse rather than race. Starting this while something it depends on
        -- is still coming up is how a second, rival copy of that dependency
        -- gets launched by a script that looked for a PID file too early.
        for _, needed in ipairs(service.requires_up or {}) do
            local other = find_service(handle, needed)
            if other and not Services.state(other).up then
                return { ok = false, text = string.format(
                    "%s needs %s running first, and it is not.\n\n"
                 .. "Start %s, wait for its lamp to turn green, then start this.",
                    service.name, needed, needed) }
            end
        end

        local started, text = Services.start(handle, service)
        return { ok = started, text = text, log = service.log }
    end

    if what == "stop" then
        local stopped, text = Services.stop(handle, service)
        return { ok = stopped, text = text, log = service.log }
    end

    return { ok = false, text = "Unknown action: " .. tostring(what) }
end
-- }}}

-- {{{ Menu.write_key(server, name, credential)
-- Write a credential from the page into its file.
--
-- Order matters and is the order a person would type by hand: create it empty,
-- narrow the permissions, THEN put the secret in. Writing first and chmod-ing
-- after leaves a window -- brief, and real -- where the credential is
-- world-readable on disk.
--
-- No elevated permission is involved anywhere. The file lives in neuron's own
-- directory and is owned by whoever runs neuron, which is whoever is reading
-- this page.
function Menu.write_key(server, name, credential)
    local handle = server.handle

    local path = ({ ["soap.key"] = handle.soap_key_path,
                    ["api.key"]  = handle.api_key_path })[name]

    if not path then
        return { ok = false, text = "There is no key called '"
            .. tostring(name) .. "'. This page knows soap.key and api.key." }
    end

    credential = tostring(credential or ""):gsub("^%s+", ""):gsub("%s+$", "")

    if credential == "" then
        return { ok = false, text = "Nothing was typed, so nothing was written. "
            .. "The existing file, if any, is untouched." }
    end

    if credential:find("=") then
        return { ok = false, text =
            "That contains an equals sign, which means it is probably a whole "
         .. "config line rather than the secret. Paste only the part after the "
         .. "equals sign -- if the line is NEURON_API_KEY=sk-abc, type sk-abc." }
    end

    local directory = path:match("^(.*)/[^/]*$")
    os.execute(string.format("mkdir -p '%s' && chmod 700 '%s'",
        directory, directory))

    -- Empty first, narrowed second, filled third.
    os.execute(string.format("touch '%s' && chmod 600 '%s'", path, path))

    local file = io.open(path, "w")
    if not file then
        return { ok = false, text = "Could not write " .. path
            .. ". The directory exists and is writable by whoever runs neuron, "
            .. "so this is unusual -- check the terminal the menu was started "
            .. "from." }
    end

    file:write(credential)
    file:close()
    os.execute(string.format("chmod 600 '%s'", path))

    return { ok = true, text = string.format(
        "Wrote %d characters to %s, mode 600. Nothing else needs changing -- "
     .. "the path was already configured.", #credential, path) }
end
-- }}}

-- {{{ Menu.clear_key(server, name)
-- Remove a credential.
--
-- An actual delete rather than an empty file, because an empty key file is a
-- key file that fails a permission check somewhere and reports something
-- confusing. Absent is a state everything already handles well.
function Menu.clear_key(server, name)
    local handle = server.handle

    local path = ({ ["soap.key"] = handle.soap_key_path,
                    ["api.key"]  = handle.api_key_path })[name]

    if not path then
        return { ok = false, text = "There is no key called '"
            .. tostring(name) .. "'." }
    end

    if not io.open(path, "r") then
        return { ok = false, text = name .. " is already gone." }
    end

    os.remove(path)

    return { ok = true, text = string.format(
        "Removed %s.\n\nWhatever it was for now falls back to whatever "
     .. "config/asking.lua says happens without it -- for api.key that is the "
     .. "bench model, if one is running.", path) }
end
-- }}}

-- {{{ Menu.say(server, name, command)
function Menu.say(server, name, command)
    local service, Services = find_service(server.handle, name)

    if not service then
        return { ok = false, text = "There is no service called '"
            .. tostring(name) .. "'." }
    end

    local answer, why = Services.say(server.handle, service, command)

    if not answer then
        return { ok = false, text = why }
    end

    return { ok = true, text = answer }
end
-- }}}

-- {{{ Menu.log(server, name, lines)
function Menu.log(server, name, lines)
    local service, Services = find_service(server.handle, name)

    if not service then
        return "There is no service called '" .. tostring(name) .. "'."
    end

    -- ONE FILE: what the server printed.
    --
    -- There were two panes with a divider, and the top one was a strict subset
    -- of the bottom one -- both of AzerothCore's appenders are attached to the
    -- same loggers, so its own log file gets a copy of what stdout already has,
    -- minus everything printed before logging was configured and minus
    -- whatever a crash writes straight to the terminal. See 058-services.lua.
    -- What neuron captured, when it started this service. Otherwise the
    -- server's own log, if its configuration named one. Otherwise nothing --
    -- and the button that leads here is disabled, so nothing is what somebody
    -- would have to work to reach.
    local path = service.log
    local captured = io.open(service.log, "r")

    if captured then
        captured:close()
    elseif service.server_log and io.open(service.server_log, "r") then
        path = service.server_log
    else
        return "Nothing to show.\n\n"
            .. service.name .. " was not started from here, so neuron captured "
            .. "no output, and\nits configuration does not say where it writes "
            .. "its own log."
    end

    local body = Services.colourise(Services.tail(path, lines or 200))

    return body
end
-- }}}

-- {{{ conversation routes
-- Every conversation on the menu's own port, addressed by id.
--
-- One port was the point: a process per conversation meant a port per
-- conversation, and anything reachable from another machine would then need a
-- router opening ports on demand. The menu already listens; conversations live
-- under it.
-- {{{ re_derive(server)
-- Rebuild the handle from what is now on disk.
--
-- WHY THIS IS POSSIBLE AT ALL: everything the handle holds -- the three
-- database names, the install directory, the config paths, the Lua script
-- corpus -- is DERIVED from two files, config/deployment.lua and the
-- deployment's own .profile. Nothing is held open across a request: the cold
-- hand runs the deployment's mysql binary per call, the live hand speaks HTTP
-- per call, the pages are read off disk per request. There is no connection
-- pool to drain and no file descriptor pointing at the old world.
--
-- So changing the profile is a change to a file, and picking it up is reading
-- the file again. The menu used to say "restart to pick it up", which was true
-- of nothing except the fact that nobody had written this function.
--
-- `sibling` loads with dofile, which re-executes, so this copy of the
-- deployment module has an empty cache and reads from disk. forget() is called
-- anyway, because relying on that is relying on how the loader happens to work
-- today.
local function re_derive(server)
    local Deployment = sibling(server.handle.neuron_root, "000-deployment.lua")
    Deployment.forget()

    local ok, fresh = pcall(Deployment.load)
    if not ok then
        return nil, tostring(fresh)
    end

    server.handle = fresh
    return fresh
end
-- }}}

local function conversation_routes(server, request, Http, Json)
    local handle = server.handle
    local Conversations = sibling(handle.neuron_root, "068-conversations.lua")
    local Transcript    = sibling(handle.neuron_root, "067-transcript.lua")

    local asked = (request.method == "POST")
        and (Json.decode(request.body) or {}) or {}
    local id = asked.id or Http.parameter(request.query, "id")

    -- {{{ the page itself
    if request.path == "/chat" then
        local file = io.open(handle.neuron_root .. "/assets/chat.html", "r")
        if not file then
            return 404, "the chat page is missing", Http.MIME.txt
        end
        local page = file:read("*a")
        file:close()
        return 200, page, Http.MIME.html
    end
    -- }}}

    if request.path == "/conversation/new" and request.method == "POST" then
        local new_id = Conversations.open(handle, asked.vocabulary or "world")
        return 200, Json.encode({ id = new_id,
            url = "/chat?id=" .. new_id }), Http.MIME.json
    end

    if request.path == "/faq" then
        -- One source. These lines are also written into every new
        -- conversation's transcript as its opening turn, and two copies of the
        -- same text is how the page comes to say something the model was never
        -- told.
        local vocabulary = id and Conversations.vocabulary_of(handle, id) or "world"
        local lines = Conversations.opening(handle, vocabulary) or {}

        return 200, Json.encode({ lines = Json.array(lines) }), Http.MIME.json
    end

    -- {{{ /bench -- which local model answers
    -- GET lists what the local server actually has; POST picks one.
    --
    -- On the MENU rather than in the configuration conversation, and the
    -- reason is not convenience. That conversation's whole vocabulary points
    -- at the REMOTE service -- endpoint, model name, timeout -- and it runs on
    -- the local model. A lever letting it change which model it is would be a
    -- model editing its own identity mid-sentence, and the window is meant to
    -- be a life raft: the thing you open when nothing works. Choosing which
    -- raft is a decision from outside the raft.
    -- {{{ /guide -- how to get a local model running
    -- A page rather than a section, because it is read once, by somebody who
    -- does not have one yet, and never again.
    if request.path == "/guide" then
        local file = io.open(handle.neuron_root .. "/assets/guide.html", "r")
        if not file then
            return 404, "the guide is missing", Http.MIME.txt
        end
        local page = file:read("*a")
        file:close()
        return 200, page, Http.MIME.html
    end
    -- }}}

    -- {{{ /server -- how to get AzerothCore running
    if request.path == "/server" then
        local file = io.open(handle.neuron_root .. "/assets/server.html", "r")
        if not file then
            return 404, "the server guide is missing", Http.MIME.txt
        end
        local page = file:read("*a")
        file:close()
        return 200, page, Http.MIME.html
    end
    -- }}}

    -- {{{ /known-good -- which AzerothCore commit this deployment is built from
    -- ASKED OF THE DEPLOYMENT, never written down.
    --
    -- A version in a document is a version that is wrong the first time
    -- somebody updates and does not think of the document. This reads the git
    -- head of the source tree neuron is pointed at, which is by definition the
    -- commit that built the server you are running -- so it cannot drift, and
    -- there is nothing to remember to update.
    if request.path == "/known-good" then
        local repo = handle.root .. "/source-beta"

        local pipe = io.popen(string.format(
            "git -C %s log -1 --format=%%H%%x09%%cd --date=short 2>/dev/null",
            "'" .. repo:gsub("'", "'\\''") .. "'"), "r")

        local line = pipe and (pipe:read("*l") or "") or ""
        if pipe then pipe:close() end

        local commit, when = line:match("^(%x+)\t(%S+)$")

        if not commit then
            return 200, Json.encode({ why = string.format(
                "no git history at %s, so the version cannot be named", repo) }),
                Http.MIME.json
        end

        return 200, Json.encode({ commit = commit, when = when }),
               Http.MIME.json
    end
    -- }}}

    -- {{{ /deployment/set -- state a value neuron would otherwise work out
    -- Every override goes through here, checked before it is written. An
    -- override that points nowhere is worse than none at all: detection would
    -- have found something, and now it is skipped in favour of a path with
    -- nothing behind it.
    if request.path == "/deployment/set" and request.method == "POST" then
        local Overrides = sibling(handle.neuron_root, "074-overrides.lua")

        local key   = tostring(asked.key or "")
        local value = asked.value
        if value == "" then value = nil end

        -- {{{ CHECKS
        -- What each override must be true of before it is worth writing. A
        -- dispatch table, so adding a settable value is one row.
        local CHECKS = {
            config_dir = function(path)
                if not Overrides.readable_dir(path) then
                    return "there is no directory at " .. path .. "."
                end
                local probe = io.open(path .. "/worldserver.conf", "r")
                if not probe then
                    return path .. " has no worldserver.conf in it.\n\n"
                        .. "That file is where neuron reads the database "
                        .. "connection, the ports and the level cap, so a "
                        .. "directory without one has nothing it needs.\n\n"
                        .. "Is it still worldserver.conf.dist? That is the "
                        .. "template; copy it to the name without .dist."
                end
                probe:close()
            end,

            worldserver_conf = function(path)
                local probe = io.open(path, "r")
                if not probe then
                    return "there is no file at " .. path .. "."
                end
                probe:close()
            end,

            authserver_conf = function(path)
                local probe = io.open(path, "r")
                if not probe then
                    return "there is no file at " .. path .. "."
                end
                probe:close()
            end,

            mysql_client = function(path)
                if not Overrides.executable(path) then
                    return path .. " is not a program this user can run.\n\n"
                        .. "neuron runs a mysql client rather than linking a "
                        .. "driver, so this has to be the binary itself."
                end
            end,
        }
        -- }}}

        if value and CHECKS[key] then
            local trouble = CHECKS[key](value)
            if trouble then
                return 200, Json.encode({ ok = false, text = trouble
                    .. "\n\nNothing was changed." }), Http.MIME.json
            end
        end

        local ok, why = Overrides.set(handle, key, value)
        if not ok then
            return 200, Json.encode({ ok = false, text = why }), Http.MIME.json
        end

        local fresh, trouble = re_derive(server)
        if not fresh then
            return 200, Json.encode({ ok = false, text = string.format(
                "config/deployment.lua now says %s, and the deployment cannot "
             .. "be read back:\n\n%s", key, trouble) }), Http.MIME.json
        end

        return 200, Json.encode({ ok = true, text = value
            and string.format("%s is now: %s", key, value)
            or  string.format("%s goes back to being worked out.", key) }),
            Http.MIME.json
    end
    -- }}}

    -- {{{ /deployment/account -- neuron's own game-master account
    -- A name and a password, set together, because they are one credential and
    -- half of one is not usable. The name goes into config/deployment.lua and
    -- the password into secrets/soap.key -- never the same file, and never
    -- the same kind of file: one is a setting somebody reads, the other is a
    -- secret nothing reads back.
    if request.path == "/deployment/account" and request.method == "POST" then
        local Overrides = sibling(handle.neuron_root, "074-overrides.lua")

        local account  = tostring(asked.account or ""):gsub("%s", "")
        local password = tostring(asked.password or "")

        if account == "" then
            return 200, Json.encode({ ok = false, text =
                "Which account? It is a game account with game-master rights, "
             .. "created in the worldserver console:\n\n"
             .. "  account create neuron a-password\n"
             .. "  account set gmlevel neuron 3 -1" }), Http.MIME.json
        end

        local ok, why = Overrides.set(handle, "soap_account", account)
        if not ok then
            return 200, Json.encode({ ok = false, text = why }), Http.MIME.json
        end

        -- The password is optional on a change of name alone. Somebody
        -- renaming the account keeps the key they already wrote, and asking
        -- them to retype a secret they cannot see is how a working setup gets
        -- broken by a form.
        local said = "The game master account is now " .. account .. "."

        if password ~= "" then
            -- Through the menu's own key writer, which creates the file empty,
            -- narrows its permissions, and only then puts the secret in. The
            -- other order leaves the secret world-readable for however long the
            -- chmod takes.
            local answer = Menu.write_key(server, "soap.key", password)
            local wrote, key_why = answer.ok, answer.text
            if not wrote then
                return 200, Json.encode({ ok = false, text = string.format(
                    "The account name was changed to %s, and its password "
                 .. "could not be written:\n\n%s", account, key_why) }),
                    Http.MIME.json
            end
            said = said .. "\nIts password was written to "
                .. handle.soap_key_path .. "."
        else
            said = said .. "\nIts password was left as it was."
        end

        local fresh, trouble = re_derive(server)
        if not fresh then
            return 200, Json.encode({ ok = false,
                text = said .. "\n\nBut the deployment cannot be read back:\n"
                    .. trouble }), Http.MIME.json
        end

        return 200, Json.encode({ ok = true, text = said }), Http.MIME.json
    end
    -- }}}

    -- {{{ /asking -- every setting for either model
    -- ONE ROUTE FOR BOTH ROLES, because they have the same settings. What
    -- differs is only where they are written: the game master's are the top
    -- level of config/asking.lua and the assistant's are inside its bench
    -- block. Two forms with one shape rather than two shapes.
    --
    -- Every field is optional. What is not sent is left as it was, so changing
    -- a port does not require retyping a model name.
    if request.path == "/asking" and request.method == "POST" then
        local Levers = sibling(handle.neuron_root, "062-asking-levers.lua")

        local role = asked.role
        if role ~= "configured" and role ~= "bench" then
            return 200, Json.encode({ ok = false, text =
                "Which model? 'configured' is the game master, 'bench' is the "
             .. "configuration assistant." }), Http.MIME.json
        end

        local asking = handle.asking or {}
        local target = (role == "bench") and (asking.bench or {}) or asking

        local write = (role == "bench")
            and function(key, value, quoted)
                return Levers.rewrite_bench(handle, key, value, quoted)
            end
            or function(key, value, quoted)
                return Levers.rewrite(handle, key, value, quoted)
            end

        local changed = {}

        -- {{{ the address, rebuilt from its parts
        -- Kept as one string in the config because that is what curl is handed,
        -- and offered as four fields because that is what somebody knows. The
        -- scheme is one of them: an assistant pointed at a hosted service needs
        -- https, and a url builder that always wrote http:// was a wall.
        if asked.scheme or asked.host or asked.port or asked.path then
            local was = target.url or "http://127.0.0.1:11434/api/chat"

            local scheme = asked.scheme
                or was:match("^(https?)://") or "http"
            local host = (asked.host ~= "" and asked.host)
                or was:match("^https?://([^:/]+)") or "127.0.0.1"
            local port = (asked.port ~= "" and asked.port)
                or was:match("^https?://[^:/]+:(%d+)")
            local path = (asked.path ~= "" and asked.path)
                or was:match("^https?://[^/]+(/.*)$") or "/"

            if port and not tostring(port):match("^%d+$") then
                return 200, Json.encode({ ok = false, text = string.format(
                    "'%s' is not a port. It is a number from 1 to 65535 -- "
                 .. "ollama uses 11434, and a hosted service over https uses "
                 .. "443, which can be left blank.", tostring(port)) }),
                    Http.MIME.json
            end

            if path:sub(1, 1) ~= "/" then path = "/" .. path end

            -- A blank port means the scheme's own, which is what a hosted
            -- address looks like written down: no colon, no number.
            local url = port and port ~= ""
                and string.format("%s://%s:%s%s", scheme, host, port, path)
                or  string.format("%s://%s%s", scheme, host, path)

            local ok, why = write("url", url, true)
            if not ok then
                return 200, Json.encode({ ok = false, text = why }), Http.MIME.json
            end
            table.insert(changed, "address " .. url)
        end
        -- }}}

        if asked.model and asked.model ~= "" then
            local ok, why = write("model", asked.model, true)
            if not ok then
                return 200, Json.encode({ ok = false, text = why }), Http.MIME.json
            end
            table.insert(changed, "model " .. asked.model)
        end

        if asked.dialect and asked.dialect ~= "" then
            local Dialects = sibling(handle.neuron_root, "056-dialects.lua")
            local known, dialect_why = Dialects.of(asked.dialect)
            if not known then
                return 200, Json.encode({ ok = false, text = dialect_why }),
                    Http.MIME.json
            end
            local ok, why = write("dialect", asked.dialect, true)
            if not ok then
                return 200, Json.encode({ ok = false, text = why }), Http.MIME.json
            end
            table.insert(changed, "format " .. asked.dialect)
        end

        if asked.timeout and asked.timeout ~= "" then
            local seconds = tonumber(asked.timeout)
            if not seconds or seconds < 1 then
                return 200, Json.encode({ ok = false, text = string.format(
                    "'%s' is not a number of seconds.", tostring(asked.timeout))
                }), Http.MIME.json
            end
            local ok, why = write("timeout_seconds", math.floor(seconds), false)
            if not ok then
                return 200, Json.encode({ ok = false, text = why }), Http.MIME.json
            end
            table.insert(changed, "timeout " .. math.floor(seconds) .. "s")
        end

        if #changed == 0 then
            return 200, Json.encode({ ok = false,
                text = "Nothing was given to change." }), Http.MIME.json
        end

        local fresh, trouble = re_derive(server)
        if not fresh then
            return 200, Json.encode({ ok = false, text =
                "Written, and the configuration cannot be read back:\n\n"
             .. trouble }), Http.MIME.json
        end

        return 200, Json.encode({ ok = true,
            text = (role == "bench" and "The configuration assistant"
                                     or "The game master")
                .. " now uses:\n  " .. table.concat(changed, "\n  ") }),
            Http.MIME.json
    end
    -- }}}

    -- {{{ /deployment/find-config -- look for a server config
    -- The same shape as finding a mysql client, and for the same reason: the
    -- answer is a list, every hit is offered, and an empty list is an answer.
    --
    -- Searched under the deployment root only. A config found somewhere else
    -- on the machine belongs to a different install, and offering it is how
    -- neuron ends up reading one server's settings while driving another.
    if request.path == "/deployment/find-config" then
        local wanted = Http.parameter(request.query, "name") or "worldserver.conf"

        if wanted ~= "worldserver.conf" and wanted ~= "authserver.conf" then
            return 200, Json.encode({ found = Json.array(),
                text = "Only worldserver.conf and authserver.conf are looked "
                    .. "for." }), Http.MIME.json
        end

        -- Four levels down, which reaches installed-files-<profile>/etc and
        -- env/dist/etc without walking a whole source tree.
        local search = io.popen(string.format(
            "find %s -maxdepth 4 -name %s -type f 2>/dev/null | head -20",
            "'" .. handle.root:gsub("'", "'\\''") .. "'",
            "'" .. wanted .. "'"), "r")

        local found = Json.array()

        if search then
            for path in search:lines() do
                -- Whether it is really one, rather than whether it is named
                -- like one. A .conf.dist that somebody renamed, or a config
                -- from a half-finished install, opens fine and says nothing.
                local file = io.open(path, "r")
                local usable = false
                if file then
                    usable = (file:read(200000) or ""):find("DatabaseInfo", 1, true)
                        ~= nil
                    file:close()
                end
                table.insert(found, { path = path, usable = usable })
            end
            search:close()
        end

        return 200, Json.encode({ found = found }), Http.MIME.json
    end
    -- }}}

    -- {{{ /deployment/check-account -- does this account exist, and can it
    -- SOAP HAS NO KEY FILE. It is HTTP Basic authentication against a GAME
    -- ACCOUNT: the worldserver looks the name up with AccountMgr::GetId,
    -- checks the password, and refuses anything below SEC_ADMINISTRATOR. So
    -- there is nothing about the file to detect -- it is neuron's own, holding
    -- the password of an account neuron picked.
    --
    -- What IS checkable is the account. It is a row in the auth database, and
    -- its security level is another row, so both can be looked at without
    -- sending anything anywhere. That turns "I typed a name" into "that
    -- account exists and has administrator rights", which is the difference
    -- between a setting that looks right and one that is.
    if request.path == "/deployment/check-account" then
        local ColdHand = sibling(handle.neuron_root, "002-cold-hand.lua")

        local name = handle.soap_account

        if not name or name == "" then
            return 200, Json.encode({ ok = false,
                text = "No account is set." }), Http.MIME.json
        end

        local rows, why = ColdHand.read(handle, handle.db_auth,
            "SELECT a.id, IFNULL(MAX(g.gmlevel), 0) AS gmlevel "
         .. "FROM account a LEFT JOIN account_access g ON g.id = a.id "
         .. "WHERE UPPER(a.username) = UPPER(?) GROUP BY a.id", { name })

        if not rows then
            return 200, Json.encode({ ok = false, text =
                "The account could not be looked up:\n\n" .. tostring(why)
             .. "\n\nThe database has to be running for this."}), Http.MIME.json
        end

        if #rows == 0 then
            return 200, Json.encode({ ok = false, text = string.format(
                "There is no account called %s.\n\n"
             .. "Create it in the worldserver console:\n"
             .. "  account create %s a-password\n"
             .. "  account set gmlevel %s 3 -1", name, name, name) }),
                Http.MIME.json
        end

        local level = tonumber(rows[1].gmlevel) or 0

        -- Three is SEC_ADMINISTRATOR, which is what the worldserver's SOAP
        -- handler requires. Anything below it authenticates and is then
        -- refused, which reads as a wrong password.
        if level < 3 then
            return 200, Json.encode({ ok = false, text = string.format(
                "%s exists, and its game-master level is %d.\n\n"
             .. "The console needs 3. Below that the login succeeds and every "
             .. "command is refused, which looks exactly like a wrong "
             .. "password.\n\n"
             .. "  account set gmlevel %s 3 -1", name, level, name) }),
                Http.MIME.json
        end

        -- Half an answer is not a pass. The account exists and neuron cannot
        -- log in as it, which is a working account and a broken setting -- and
        -- reporting that as success is how somebody stops looking.
        local Keys = sibling(handle.neuron_root, "052-keys.lua")
        local have_password = Keys.present(handle.soap_key_path, "the soap key")

        if not have_password then
            return 200, Json.encode({ ok = false, text = string.format(
                "%s exists, with game-master level %d -- and its password has "
             .. "not been written here.\n\n"
             .. "neuron cannot log in as it until that is done. Press change "
             .. "and give the password you created the account with.",
                name, level) }), Http.MIME.json
        end

        return 200, Json.encode({ ok = true, text = string.format(
            "%s exists, with game-master level %d, and its password is here.",
            name, level) }), Http.MIME.json
    end
    -- }}}

    -- {{{ /deployment/find-mysql -- look for a client to run
    -- Everywhere a mysql client plausibly is, on one machine.
    --
    -- Somebody whose deployment builds its own -- this one does -- will find
    -- nothing useful here, and that is fine: the answer is a list and an empty
    -- list is an answer. Somebody on a distribution that packages MySQL or
    -- MariaDB gets the path they would otherwise have had to know.
    --
    -- Every hit is offered rather than the first one taken. A machine with two
    -- clients has them for a reason, and picking silently is how neuron ends
    -- up speaking to the wrong server with results that look right.
    if request.path == "/deployment/find-mysql" then
        local seen, found = {}, Json.array()

        -- {{{ offer(path)
        local function offer(path)
            path = (path or ""):gsub("%s+$", "")
            if path == "" or seen[path] then return end
            seen[path] = true

            local probe = io.popen(string.format(
                "%s --version 2>/dev/null | head -1",
                "'" .. path:gsub("'", "'\\''") .. "'"), "r")

            local version = probe and (probe:read("*l") or "") or ""
            if probe then probe:close() end

            table.insert(found, { path = path,
                version = version ~= "" and version or "would not say" })
        end
        -- }}}

        -- What the shell would run, first, since that is what somebody typing
        -- `mysql` would get.
        -- `mysql` only. AzerothCore explicitly refuses MariaDB, so offering
        -- its client would be offering a road that ends.
        local which = io.popen("command -v mysql 2>/dev/null", "r")
        if which then
            for line in which:lines() do offer(line) end
            which:close()
        end

        -- Then the places a client lands that is not on PATH: this
        -- deployment's own build, and the usual package locations.
        local elsewhere = io.popen(string.format(
            "ls -1 %s/mysql/installed-files/bin/mysql "
         .. "/usr/local/mysql/bin/mysql /opt/mysql/bin/mysql "
         .. "/usr/local/bin/mysql 2>/dev/null",
            "'" .. handle.root:gsub("'", "'\\''") .. "'"), "r")

        if elsewhere then
            for line in elsewhere:lines() do offer(line) end
            elsewhere:close()
        end

        return 200, Json.encode({ found = found, current = handle.mysql_binary }),
               Http.MIME.json
    end
    -- }}}

    -- {{{ /library -- every word, grouped by who can say it
    if request.path == "/library" then
        return 200, Json.encode({ groups = Json.array(library(handle)) }),
               Http.MIME.json
    end
    -- }}}

    if request.path == "/bench" then
        local asking = handle.asking

        if not asking or not asking.bench then
            return 200, Json.encode({ ok = false, text =
                "config/asking.lua describes no local model, so there is "
             .. "nothing here to choose between." }), Http.MIME.json
        end

        local Setup = sibling(handle.neuron_root, "063-setup.lua")

        local address, port =
            asking.bench.url:match("^https?://([^:/]+):?(%d*)")
        port = tonumber(port) or 11434

        local names = address and Setup.models_at(address, port)

        -- The address, changed the same way the model is. It is the setting
        -- most likely to be wrong and the only one somebody cannot guess from
        -- the page: ollama binds 127.0.0.1:11434, this deployment's is on
        -- another machine entirely, and until now the only way to say so was
        -- to edit config/asking.lua by hand.
        -- An address given as a host and a port, which is what somebody
        -- actually knows. The path is almost always /api/chat and almost never
        -- the thing that is wrong; splitting it out means two small correct
        -- answers instead of one long string to get right in three places at
        -- once.
        if request.method == "POST" and (asked.host or asked.port) then
            local was = asking.bench.url or ""

            local host = tostring(asked.host or ""):gsub("%s", "")
            local port = tostring(asked.port or ""):gsub("%s", "")
            local path = was:match("^https?://[^/]+(/.*)$") or "/api/chat"

            if host == "" then
                host = was:match("^https?://([^:/]+)") or "127.0.0.1"
            end
            if port == "" then
                port = was:match("^https?://[^:/]+:(%d+)") or "11434"
            end

            if not port:match("^%d+$") then
                return 200, Json.encode({ ok = false, text = string.format(
                    "'%s' is not a port. It is a number between 1 and 65535 -- "
                 .. "ollama's own default is 11434.", port) }), Http.MIME.json
            end

            asked.url = string.format("http://%s:%s%s", host, port, path)
        end

        if request.method == "POST" and asked.url then
            local url = tostring(asked.url):gsub("%s+", "")

            if not url:match("^https?://[^/]+") then
                return 200, Json.encode({ ok = false, text = string.format(
                    "'%s' is not an address neuron can dial.\n\n"
                 .. "It needs the scheme and the host, and the path the server "
                 .. "answers on -- for example\n"
                 .. "  http://127.0.0.1:11434/api/chat", url) }), Http.MIME.json
            end

            local Levers = sibling(handle.neuron_root, "062-asking-levers.lua")
            local ok, why = Levers.rewrite_bench(handle, "url", url, true)
            if not ok then
                return 200, Json.encode({ ok = false, text = why }), Http.MIME.json
            end

            local fresh, trouble = re_derive(server)
            if not fresh then
                return 200, Json.encode({ ok = false, text =
                    "config/asking.lua now says " .. url .. ", but it cannot "
                 .. "be read back:\n\n" .. trouble }), Http.MIME.json
            end

            return 200, Json.encode({ ok = true, text =
                "Local model now at: " .. url
             .. "\n\nPress check to see whether anything answers there." }),
                Http.MIME.json
        end

        if request.method == "POST" then
            local wanted = asked.model

            local known = false
            for _, name in ipairs(names or {}) do
                if name == wanted then known = true end
            end

            if not known then
                return 200, Json.encode({ ok = false, text = string.format(
                    "%s does not have '%s'.\n\nPull it first:  ollama pull %s",
                    asking.bench.url, tostring(wanted),
                    tostring(wanted):gsub(":latest$", "")) }), Http.MIME.json
            end

            local Levers = sibling(handle.neuron_root, "062-asking-levers.lua")
            local ok, why = Levers.rewrite_bench(handle, "model", wanted, true)

            if not ok then
                return 200, Json.encode({ ok = false, text = why }), Http.MIME.json
            end

            local fresh, trouble = re_derive(server)
            if not fresh then
                return 200, Json.encode({ ok = false, text =
                    "config/asking.lua now names " .. wanted .. ", but it "
                 .. "cannot be read back:\n\n" .. trouble }), Http.MIME.json
            end

            return 200, Json.encode({ ok = true, text = string.format(
                'Switching local model to: "%s"', wanted) }), Http.MIME.json
        end

        -- Tool-capable ones first, then the rest, each alphabetical. A model
        -- with no tool-calling template does not error -- it writes PROSE
        -- about the tools it would call -- so the distinction is the single
        -- most useful thing this list can say.
        local able, unable = {}, {}
        for _, name in ipairs(names or {}) do
            table.insert(Setup.can_call_tools(name) and able or unable, name)
        end
        table.sort(able)
        table.sort(unable)

        local listed = Json.array()
        for _, name in ipairs(able) do
            table.insert(listed, { name = name, tools = true })
        end
        for _, name in ipairs(unable) do
            table.insert(listed, { name = name, tools = false })
        end

        return 200, Json.encode({
            ok      = names ~= nil,
            url     = asking.bench.url,
            current = asking.bench.model,
            models  = listed,
            text    = names and "" or (asking.bench.url
                .. " did not answer, so there is no list to choose from."),
        }), Http.MIME.json
    end
    -- }}}

    if request.path == "/profiles" then
        -- Which profiles this deployment has BUILT, from the directories that
        -- exist rather than from a list somebody maintains. A profile with no
        -- installed-files directory has never been built and pointing at it
        -- would produce a deployment with no server.
        -- The profile names come from the deployment's own definitions, and
        -- the built ones are the intersection with what exists on disk.
        --
        -- Not from the directories alone: `installed-files-shadow` is not a
        -- profile at all. Shadow is the staging area of the deployment's
        -- build workflow -- compile builds into it, validate tests it, promote
        -- copies it over the real installation. Offering it as something to run
        -- would point neuron at a half-finished build.
        local defined = {}
        local definitions = io.open(handle.root .. "/scripts/profiles", "r")
        if definitions then
            local text = definitions:read("*a")
            definitions:close()
            local block = text:match("PROFILE_REPO=%b()")
            for name in (block or ""):gmatch('%["([%w_]+)%"%]') do
                defined[name] = true
            end
        end

        local listing = io.popen(string.format(
            "ls -d %s 2>/dev/null", "'" .. handle.root .. "'/installed-files-*"), "r")

        local built = {}
        if listing then
            for path in listing:lines() do
                local name = path:match("installed%-files%-(.+)$")
                if name and (defined[name] or next(defined) == nil)
                         and name ~= "shadow" then
                    table.insert(built, name)
                end
            end
            listing:close()
        end

        -- What is currently selected, from the deployment's own file.
        local current = handle.deployment_profile

        if request.method == "POST" then
            local wanted = asked.profile

            local known = false
            for _, name in ipairs(built) do
                if name == wanted then known = true end
            end

            if not known then
                return 200, Json.encode({ ok = false, text = string.format(
                    "'%s' has not been built. This deployment has: %s.",
                    tostring(wanted), table.concat(built, ", ")) }), Http.MIME.json
            end

            -- Refuse while anything is running.
            --
            -- Switching points neuron at a different set of databases while a
            -- worldserver is still holding the old ones in memory. Everything
            -- would appear to work and every answer would be about a different
            -- world.
            local Services = sibling(handle.neuron_root, "058-services.lua")
            local running = {}
            for _, service in ipairs(Services.of(handle)) do
                -- `profile_agnostic` skips ollama. It holds no world and no
                -- database, so switching underneath it changes nothing about
                -- what it would say.
                if not service.profile_agnostic
                   and Services.state(service).up then
                    table.insert(running, service.name)
                end
            end

            if #running > 0 then
                return 200, Json.encode({ ok = false, text = string.format(
                    "Stop %s first.\n\nSwitching profiles points neuron at "
                 .. "different databases while a running server still holds the "
                 .. "old ones in memory. Everything would appear to work and "
                 .. "every answer would be about a different world.",
                    table.concat(running, " and ")) }), Http.MIME.json
            end

            local file = io.open(handle.root .. "/.profile", "w")
            if not file then
                return 200, Json.encode({ ok = false,
                    text = "Cannot write " .. handle.root .. "/.profile" }),
                    Http.MIME.json
            end
            file:write(wanted .. "\n")
            file:close()

            -- Picked up here and now. Everything the menu knows about a profile
            -- comes from this file, and nothing is held open across a request,
            -- so re-reading it IS the switch.
            local fresh, trouble = re_derive(server)

            if not fresh then
                return 200, Json.encode({ ok = false, text = string.format(
                    "The profile file now says '%s', but neuron cannot read "
                 .. "the deployment back:\n\n%s", wanted, trouble) }),
                    Http.MIME.json
            end

            return 200, Json.encode({ ok = true, text = string.format(
                'Switching to profile: "%s"',
                wanted:sub(1, 1):upper() .. wanted:sub(2)) }), Http.MIME.json
        end

        return 200, Json.encode({ current = current, built = built }),
               Http.MIME.json
    end

    if request.path == "/deployment" and request.method == "POST" then
        local root = tostring(asked.root or ""):gsub("/+$", "")

        -- ONE MARKER, and it is the server's own configuration.
        --
        -- This used to require `.profile`, `mysql/` and an `installed-files-*`
        -- -- three things that belong to this project's way of arranging a
        -- deployment rather than to AzerothCore. A stock install has none of
        -- them and was refused, correctly by its own rule and uselessly in
        -- fact, since everything neuron needs was sitting in `env/dist/etc`.
        --
        -- A worldserver.conf is the thing without which there is genuinely
        -- nothing to do: no database connection, no ports, no level cap.
        local found = nil

        for _, where in ipairs({ "/installed-files-*/etc", "/env/dist/etc",
                                 "/etc" }) do
            local probe = io.popen(string.format(
                "ls -d %s/worldserver.conf 2>/dev/null | head -1",
                "'" .. root:gsub("'", "'\\''") .. "'" .. where), "r")
            local line = probe and (probe:read("*l") or "") or ""
            if probe then probe:close() end
            if line ~= "" then found = line break end
        end

        if not found then
            return 200, Json.encode({ ok = false, text = string.format(
                "%s has no worldserver.conf, so neuron cannot tell what is "
             .. "there.\n\n"
             .. "Looked in:\n"
             .. "  installed-files-<profile>/etc/\n"
             .. "  env/dist/etc/\n"
             .. "  etc/\n\n"
             .. "Everything neuron needs about a deployment -- the database "
             .. "connection, the ports, the level cap -- is in that file.\n\n"
             .. "To debug:\n"
             .. "  Has the server been installed, or only built?\n"
             .. "    A build leaves binaries; installing writes the configs.\n"
             .. "  Are they still .conf.dist files?\n"
             .. "    Those are templates. Copy each to the name without "
             .. ".dist.\n"
             .. "  Somewhere else entirely?\n"
             .. "    Set config_dir in config/deployment.lua.\n\n"
             .. "Nothing was changed -- the configured deployment is left "
             .. "exactly as it was.", root) }), Http.MIME.json
        end

        -- One line in one file. Rewritten in place so every comment around it
        -- survives, the same way the asking config is edited.
        local path = handle.neuron_root .. "/config/deployment.lua"
        local file = io.open(path, "r")
        if not file then
            return 200, Json.encode({ ok = false,
                text = "config/deployment.lua is not there." }), Http.MIME.json
        end
        local text = file:read("*a")
        file:close()

        local changed, count = text:gsub('(\n    root%s*=%s*)"[^"]*"',
            "%1" .. string.format("%q", root), 1)

        if count == 0 then
            return 200, Json.encode({ ok = false,
                text = "config/deployment.lua has no root line to change." }),
                Http.MIME.json
        end

        local out = io.open(path, "w")
        out:write(changed)
        out:close()

        -- Same as the profile switch: this is one line in one file, and
        -- everything downstream is derived from it on demand.
        local fresh, trouble = re_derive(server)

        if not fresh then
            return 200, Json.encode({ ok = false, text = string.format(
                "config/deployment.lua now points at %s, but neuron cannot "
             .. "read that deployment back:\n\n%s\n\nThe file was changed; "
             .. "the menu is still describing the old one.", root, trouble) }),
                Http.MIME.json
        end

        -- A deployment may have no profiles at all, which is not an absence
        -- worth apologising for -- it is what one world with one set of
        -- databases looks like.
        return 200, Json.encode({ ok = true, text = string.format(
            "Switching to deployment: %s\n%s", root,
            fresh.profile
                and string.format("profile: \"%s\"",
                    fresh.profile:sub(1, 1):upper() .. fresh.profile:sub(2))
                or "It has no profiles: one world, one set of databases.") }),
            Http.MIME.json
    end

    if request.path == "/conversation/list" then
        return 200, Json.encode({ conversations = Transcript.list(handle, 60) }),
               Http.MIME.json
    end

    if request.path == "/conversation/text" then
        -- `said=1` asks for only what people said. That is the
        -- prior-conversation viewer on the menu: somebody scrolling last week's
        -- conversation came for the conversation, not for the instructions it
        -- was given or the eighty-line creature table in the middle of it.
        --
        -- Without it, both halves stitched -- the live chat window draws itself
        -- from this and wants the calls and their answers too.
        -- THE HUMAN HALF, always. The machine's half is never shown to a
        -- person -- not in the live window, not in the preview, not when a
        -- conversation is picked back up. That is the entire reason the split
        -- exists, and serving the stitched version to the chat page put the
        -- system prompt and every tool result straight back on screen.
        --
        -- `said=1` narrows it further, to `you` and `neuron` alone. That is the
        -- preview on the menu, where somebody is scanning a list rather than
        -- reading a conversation, and the tool lines are noise.
        local only_said = Http.parameter(request.query, "said") == "1"

        local text = only_said and Transcript.said(handle, id or "")
                                or Transcript.human(handle, id or "")

        return 200, text or "No such conversation.", Http.MIME.txt
    end

    if request.path == "/conversation/ask" and request.method == "POST" then
        local ok, answer = pcall(Conversations.ask, handle, id, asked.text,
                                 asked.model)
        if not ok then
            answer = { kind = "trouble", text = "something broke:\n" .. tostring(answer) }
        end
        return 200, Json.encode(answer), Http.MIME.json
    end

    if request.path == "/conversation/pull" and request.method == "POST" then
        local ok, answer = pcall(Conversations.pull, handle, id,
            asked.operation, asked.arguments)
        if not ok then
            answer = { kind = "trouble", text = "something broke:\n" .. tostring(answer) }
        end
        return 200, Json.encode(answer), Http.MIME.json
    end

    if request.path == "/conversation/apply" and request.method == "POST" then
        local ok, answer = pcall(Conversations.apply, handle, id, asked.plan)
        if not ok then
            answer = { kind = "trouble", text = "something broke:\n" .. tostring(answer) }
        end
        return 200, Json.encode(answer), Http.MIME.json
    end

    if request.path == "/conversation/vocabulary" then
        local Registry = sibling(handle.neuron_root, "045-toolbox/047-registry.lua")
        local vocabulary = Conversations.vocabulary_of(handle, id or "") or "world"
        local registry = Registry.load(handle.neuron_root, vocabulary)

        local words = {}
        for _, operation in ipairs(registry and registry.ordered or {}) do
            local params = {}
            for _, parameter in ipairs(operation.params) do
                table.insert(params, { name = parameter.name,
                    type = parameter.type.name, required = parameter.required,
                    describes = parameter.describes })
            end
            table.insert(words, { name = operation.name, glyph = operation.kind.glyph,
                kind = operation.kind.name, summary = operation.summary,
                params = params })
        end

        return 200, Json.encode({ vocabulary = vocabulary, words = words }),
               Http.MIME.json
    end

    return nil
end
-- }}}

-- {{{ Menu.run(server)
function Menu.run(server)
    local handle = server.handle

    local Http = sibling(handle.neuron_root, "057-http.lua")
    local Json = sibling(handle.neuron_root, "001-json.lua")

    local listening, why = Http.listen(server.port, server.host)
    if not listening then
        io.stderr:write(why .. "\n")
        os.exit(1)
    end

    local page_path = handle.neuron_root .. "/assets/menu.html"

    -- {{{ read_page()
    -- The page, re-read on every request rather than held from startup.
    --
    -- It used to be read once into a local. Which meant every edit to the page
    -- silently required a restart, with nothing anywhere saying so -- a fix
    -- would be on disk, absent from the browser, and the only symptom was the
    -- old behaviour continuing exactly as before. That cost an afternoon.
    --
    -- The file is a few kilobytes on loopback. Re-reading it costs nothing and
    -- removes the entire class of "I changed it and nothing happened".
    local function read_page()
        local file = io.open(page_path, "r")
        if not file then
            return nil, "the menu page is missing at " .. page_path
        end
        local text = file:read("*a")
        file:close()
        return text
    end
    -- }}}

    local page, page_why = read_page()
    if not page then
        io.stderr:write(page_why .. "\n")
        os.exit(1)
    end

    -- Where somebody actually types to reach this.
    --
    -- Not the bind address: 0.0.0.0 is a thing a socket does, not a thing you
    -- put in a browser. When bound wide, the useful answer is this machine's
    -- own address on its network -- the one another machine would send to.
    local reachable_at = server.host
    local wide = (server.host == "0.0.0.0" or server.host == "::")

    if wide then
        reachable_at = Http.lan_address() or server.host
    end

    print("")
    print("  neuron menu   http://" .. reachable_at .. ":" .. server.port)
    print("")
    print("  deployment  " .. handle.root)
    -- A deployment with no profiles is not missing one. It has a single
    -- world and a single set of databases, which is what most AzerothCore
    -- installs are.
    print("  profile     " .. (handle.profile or "none — one world"))
    print("")

    if server.host == "127.0.0.1" then
        print("  Loopback only. Nothing on the network can reach this.")
    else
        -- Said every time, and said as what it is. There is no login on this
        -- page. Every lever it offers -- including the one that removes
        -- characters and cannot be undone -- is available to whoever opens it.
        print("  OPEN ON THE NETWORK, bound to " .. server.host .. ".")
        print("  There is no login. Anybody who can reach this address can")
        print("  pull every lever on the page, including the ones that cannot")
        print("  be undone. Fine on a network you own; nowhere else.")
    end

    print("  Ctrl-C to stop.")
    print("")

    while true do
        local client = listening:accept()

        if client then
            local request = Http.read_request(client)

            if not request then
                client:close()
            elseif request.path == "/" then
                Http.respond(client, 200, read_page() or page, Http.MIME.html)

            elseif request.path == "/faq"
                or request.path == "/profiles"
                or request.path == "/deployment"
                or request.path == "/bench"
                or request.path == "/library"
                or request.path == "/guide"
                or request.path == "/server"
                or request.path == "/known-good"
                or request.path == "/deployment/set"
                or request.path == "/deployment/account"
                or request.path == "/deployment/find-mysql"
                or request.path == "/deployment/check-account"
                or request.path == "/deployment/find-config"
                or request.path == "/asking"
                or request.path:sub(1, 6) == "/chat"
                or request.path:sub(1, 14) == "/conversation/" then
                -- Wrapped, and the failure comes back as JSON.
                --
                -- Two separate ways this used to answer with something the chat
                -- page could not parse, both reported to the person as the
                -- unhelpful "JSON.parse: unexpected character at line 1 column
                -- 1": a Lua error in a route killed the accept loop outright,
                -- and a route that matched nothing fell through to the plain
                -- sentence "no such conversation route" -- which begins with an
                -- 'n', and 'n' is where JSON.parse stops.
                --
                -- Now every answer on this path is JSON, including the answer
                -- that something broke, and the page can say what broke.
                local ran, status, body, kind =
                    pcall(conversation_routes, server, request, Http, Json)

                if not ran then
                    Http.respond(client, 500, Json.encode({
                        kind = "trouble",
                        text = "the menu server broke handling " .. request.path
                            .. ":\n" .. tostring(status) }), Http.MIME.json)
                elseif status == nil then
                    Http.respond(client, 404, Json.encode({
                        kind = "trouble",
                        text = "there is no route " .. request.path
                            .. " on this server." }), Http.MIME.json)
                else
                    Http.respond(client, status, body or "", kind or Http.MIME.txt)
                end

            elseif request.path == "/state" then
                Http.respond(client, 200,
                    Json.encode(Menu.state(server,
                        Http.parameter(request.query, "probe"))),
                    Http.MIME.json)

            elseif request.path == "/act" and request.method == "POST" then
                local asked = Json.decode(request.body) or {}
                Http.respond(client, 200,
                    Json.encode(Menu.act(server, asked.what, asked.name)),
                    Http.MIME.json)

            elseif request.path == "/key" and request.method == "POST" then
                local asked = Json.decode(request.body) or {}
                local answer = asked.clear
                    and Menu.clear_key(server, asked.name)
                    or  Menu.write_key(server, asked.name, asked.value)
                Http.respond(client, 200, Json.encode(answer), Http.MIME.json)

            elseif request.path == "/say" and request.method == "POST" then
                local asked = Json.decode(request.body) or {}
                Http.respond(client, 200,
                    Json.encode(Menu.say(server, asked.name, asked.command)),
                    Http.MIME.json)

            elseif request.path == "/log" then
                Http.respond(client, 200,
                    Menu.log(server, Http.parameter(request.query, "service")),
                    Http.MIME.txt)

            else
                Http.respond(client, 404,
                    "No such thing here. The menu serves /, /state, /act, /log "
                 .. "and /conversation.", Http.MIME.txt)
            end
        end
    end
end
-- }}}

return Menu
