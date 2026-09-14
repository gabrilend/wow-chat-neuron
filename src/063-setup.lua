--------------------------------------------------------------------------------
-- 063-setup.lua
--
-- The questions asked when there is no local model to ask them for you.
--
-- A scripted conversation, with no model behind it at all. Every line here was
-- written in advance; nothing is generated. That is the point: this runs when
-- nothing is running, and something that needed a model to help you configure a
-- model would be no help at the only moment it is wanted.
--
-- It looks like the chat it replaces -- same window, same lines, same shape --
-- because somebody who has just opened a chat window should not have to learn a
-- second interface to answer four questions.
--------------------------------------------------------------------------------

local Setup = {}

-- {{{ ollama_host_from_environment()
-- Whatever OLLAMA_HOST says, if anything.
--
-- The single line that would have prevented days of "the local model is not
-- running" about a local model that was running the whole time, on
-- 192.168.1.100:10265, because the config guessed the default port and nothing
-- ever asked the machine.
local function ollama_host_from_environment()
    local host = os.getenv("OLLAMA_HOST")
    if not host or host == "" then return nil end

    local address, port = host:match("^([^:]+):(%d+)$")
    if address then return address, tonumber(port) end

    -- A bare port, which Ollama also accepts.
    if host:match("^:?%d+$") then
        return "127.0.0.1", tonumber(host:match("(%d+)"))
    end

    return host, 11434
end
-- }}}

-- {{{ listening_ollama()
-- Any port held by a process called ollama, asked of the machine rather than
-- assumed.
local function listening_ollama()
    local pipe = io.popen(
        "ss -lntpH 2>/dev/null | grep -i ollama "
     .. "| grep -oE '[0-9.]+:[0-9]+' | head -1", "r")
    if not pipe then return nil end

    local found = (pipe:read("*l") or ""):gsub("%s", "")
    pipe:close()

    local address, port = found:match("^([%d%.]+):(%d+)$")
    if address then return address, tonumber(port) end
    return nil
end
-- }}}

-- {{{ Setup.guess()
-- The best suggestion available, and where it came from.
function Setup.guess()
    local address, port = ollama_host_from_environment()
    if address then return address, port, "OLLAMA_HOST" end

    address, port = listening_ollama()
    if address then
        -- 0.0.0.0 means every interface; something has to be dialled, and
        -- loopback is the one that always works from here.
        if address == "0.0.0.0" then address = "127.0.0.1" end
        return address, port, "a listening ollama process"
    end

    return "127.0.0.1", 11434, "the usual default"
end
-- }}}

-- {{{ models_at(address, port)
-- What that server has, asked of it.
local function models_at(address, port)
    local url = string.format("http://%s:%d/api/tags", address, port)

    local pipe = io.popen(string.format(
        "curl --silent --max-time 4 %s 2>/dev/null",
        "'" .. url:gsub("'", "'\\''") .. "'"), "r")
    if not pipe then return nil end

    local body = pipe:read("*a") or ""
    pipe:close()

    if body == "" then return nil end

    local names = {}
    for name in body:gmatch('"name"%s*:%s*"([^"]+)"') do
        table.insert(names, name)
    end

    return names
end
-- }}}

-- {{{ Setup.models_at(address, port)
-- The same question, asked from outside this file.
--
-- The menu needs it to offer a choice of local model, and there is no reason
-- for a second copy of "ask ollama what it has" to exist -- two of them is two
-- things to fix when the endpoint's shape changes.
Setup.models_at = models_at
-- }}}

-- {{{ TOOL_CAPABLE
-- Families whose Ollama builds carry a tool-calling template.
--
-- A model without one does not error -- it answers in PROSE about the tools,
-- which reads as the conversation loop being broken. Worth steering away from
-- rather than letting somebody discover.
local TOOL_CAPABLE = { "llama3.1", "llama3.2", "llama3.3", "qwen2.5", "qwen3",
                       "mistral-nemo", "mistral-small", "firefunction",
                       "command-r", "hermes3" }

-- Embedding models turn text into vectors and cannot hold a conversation at
-- all, let alone call a tool. Their names contain family names that otherwise
-- match -- "qwen3-embedding" contains "qwen3" -- so this list is checked FIRST
-- and it is why: the wizard cheerfully suggested an embedding model as the one
-- to run the world with.
local NOT_A_CHAT_MODEL = { "embed", "-bge", "rerank", "nomic-" }

-- Exposed for the same reason models_at is: the menu marks which of the
-- offered models can actually call a tool, and that judgement should be made
-- in one place.
local function can_call_tools(name)
    local lowered = name:lower()

    for _, disqualifying in ipairs(NOT_A_CHAT_MODEL) do
        if lowered:find(disqualifying, 1, true) then return false end
    end

    for _, family in ipairs(TOOL_CAPABLE) do
        if lowered:find(family, 1, true) then return true end
    end
    return false
end

Setup.can_call_tools = can_call_tools
-- }}}

-- {{{ Setup.begin(handle)
-- The opening, when a configuration window finds nothing to talk to.
function Setup.begin(handle)
    local address, port, source = Setup.guess()

    return {
        step    = "address",
        address = address,
        port    = port,
        lines = {
            "There is no local model answering, so I will ask you a few things "
         .. "myself. Nothing here is generated -- these questions are written "
         .. "down, because a model that needed a model to configure it would be "
         .. "no use at the only moment you want one.",
            "",
            "What address is the model server on?",
            string.format("  Enter for  %s   (from %s)", address, source),
        },
    }
end
-- }}}

-- {{{ Setup.answer(handle, state, said)
-- One answer, and the next question. Returns a new state and lines to print.
function Setup.answer(handle, state, said)
    said = tostring(said or ""):gsub("^%s+", ""):gsub("%s+$", "")

    -- {{{ address
    if state.step == "address" then
        if said ~= "" then state.address = said end
        state.step = "port"

        return state, {
            string.format("Address: %s", state.address),
            "",
            "What port?",
            string.format("  Enter for  %d", state.port),
        }
    end
    -- }}}

    -- {{{ port
    if state.step == "port" then
        if said ~= "" then
            local port = tonumber(said:match("%d+"))
            if not port then
                return state, { string.format(
                    "'%s' is not a port. It is a number -- Ollama's default is "
                 .. "11434. Try again, or press Enter for %d.",
                    said, state.port) }
            end
            state.port = port
        end

        local names = models_at(state.address, state.port)

        if not names then
            state.step = "address"
            return state, {
                string.format("Nothing answered at %s:%d.",
                    state.address, state.port),
                "",
                "Either it is not started --",
                "  ollama serve",
                "-- or the address is wrong. If it is running elsewhere, its own",
                "OLLAMA_HOST says where.",
                "",
                "What address is the model server on?",
                string.format("  Enter for  %s", state.address),
            }
        end

        if #names == 0 then
            state.step = "port"
            return state, {
                string.format("%s:%d answered, and has no models pulled.",
                    state.address, state.port),
                "",
                "  ollama pull qwen2.5",
                "",
                "Then press Enter here.",
            }
        end

        state.models = names
        state.step = "model"

        local lines = { string.format("%s:%d answered. It has %d model%s:",
            state.address, state.port, #names, #names == 1 and "" or "s"), "" }

        local usable = {}
        for _, name in ipairs(names) do
            if can_call_tools(name) then table.insert(usable, name) end
        end

        for _, name in ipairs(usable) do
            table.insert(lines, "  " .. name)
        end

        if #usable == 0 then
            table.insert(lines, "  (none of them can call tools)")
            table.insert(lines, "")
            table.insert(lines, "Neuron works by giving a model tools to call. A "
                .. "model without that answers in prose ABOUT the tools, which "
                .. "looks like everything being broken. Pull one that can:")
            table.insert(lines, "  ollama pull qwen2.5")
            table.insert(lines, "")
            table.insert(lines, "Then press Enter. Or type any model name to use "
                .. "it anyway.")
        else
            table.insert(lines, "")
            table.insert(lines, "Which one? Type its name, or press Enter for "
                .. usable[1] .. ".")
            state.suggested = usable[1]
        end

        return state, lines
    end
    -- }}}

    -- {{{ model
    if state.step == "model" then
        local chosen = said ~= "" and said or state.suggested

        if not chosen then
            local names = models_at(state.address, state.port)
            state.models = names or state.models
            return state, { "Still nothing to choose. Pull a model that can call "
                .. "tools, then press Enter:", "  ollama pull qwen2.5" }
        end

        state.model = chosen
        state.step  = "done"

        local written, why = Setup.write(handle, state)

        if not written then
            return state, { "Could not write config/asking.lua:", "  " .. why }
        end

        return state, {
            "Written to config/asking.lua:",
            string.format("  endpoint  http://%s:%d/api/chat",
                state.address, state.port),
            string.format("  model     %s", chosen),
            "",
            "Loading it into memory now -- the first request is the slow one, "
         .. "so it happens while you read this.",
            "",
            "Close this window and open it again, and you will be talking to it.",
        }
    end
    -- }}}

    return state, { "Setup is finished. Close this window and open it again." }
end
-- }}}

-- {{{ Setup.write(handle, state)
-- Put the answers in the config, editing the two lines and nothing else.
function Setup.write(handle, state)
    local path = handle.neuron_root .. "/config/asking.lua"

    local file = io.open(path, "r")
    if not file then return nil, "config/asking.lua is not there." end
    local text = file:read("*a")
    file:close()

    local url = string.format("http://%s:%d/api/chat", state.address, state.port)

    -- Both settings live inside the `bench` block, indented eight. The
    -- top-level `url` and `model` belong to the configured remote service and
    -- must not be touched -- which is exactly the mistake the earlier
    -- any-indentation pattern made with timeout_seconds.
    local changed = text:gsub('(\n        url%s*=%s*)"[^"]*"', "%1" .. string.format("%q", url), 1)
    changed = changed:gsub('(\n        model%s*=%s*)"[^"]*"', "%1" .. string.format("%q", state.model), 1)

    local out = io.open(path, "w")
    if not out then return nil, "config/asking.lua could not be written." end
    out:write(changed)
    out:close()

    return true
end
-- }}}

return Setup
