--------------------------------------------------------------------------------
-- 056-dialects.lua
--
-- Two ways of saying the same conversation, and the translation between them.
--
-- The loop (051-loop.lua) speaks ONE shape: a system prompt, a list of messages,
-- a list of tools, and a reply carrying content blocks and a stop reason. That
-- shape is Anthropic's, because that is what was built first, and it is now the
-- project's internal shape whether or not the request goes there.
--
-- A dialect translates that shape to and from a particular server's wire
-- format. Adding a second place to ask is therefore adding a dialect, not
-- editing the loop -- which matters because the loop holds the rule the whole
-- safety model rests on (a change is planned, never applied) and that rule
-- should not be re-implemented per provider.
--
-- THE THREE DIFFERENCES THAT ACTUALLY BITE, going to Ollama:
--
--   1. The system prompt is a top-level field for one and a message with
--      role "system" for the other.
--   2. Tool schemas are {name, description, input_schema} for one and
--      {type:"function", function:{name, description, parameters}} for the
--      other -- the same information, nested one level deeper.
--   3. Tool RESULTS are content blocks inside a user message for one, and
--      separate messages with role "tool" for the other. And Ollama's tool
--      calls carry NO ID, so the id matching the loop relies on has to be
--      invented here and stripped again on the way out.
--
-- The third is the one that silently produces a broken conversation rather than
-- an error, which is why it gets the most care below.
--------------------------------------------------------------------------------

local Dialects = {}

-- {{{ anthropic
-- The internal shape, passed through almost untouched. It is written out as a
-- dialect anyway rather than special-cased, so that "which dialect" is always a
-- lookup and never a branch.
Dialects.anthropic = {
    name = "anthropic",

    -- {{{ encode(request, asking)
    encode = function(request, asking)
        -- An empty tool list is OMITTED, not sent.
        --
        -- An empty Lua table encodes as {} and the API wants an array, so it
        -- answers "tools: Input should be a valid array" -- an HTTP 400 that
        -- looks like a malformed request and is really a Lua ambiguity. The
        -- admin model diagnosed this exactly right and correctly said it could
        -- not fix it from its side: no endpoint, model or timeout setting
        -- would have helped.
        --
        -- Omitted rather than sent as [] because a request with no tools is a
        -- request that is not doing tool use, and saying nothing is clearer
        -- than saying nothing at length.
        local tools = request.tools
        if not tools or #tools == 0 then tools = nil end

        return {
            model      = asking.model,
            max_tokens = asking.max_tokens or 8192,
            system     = request.system,
            messages   = request.messages,
            tools      = tools,
        }
    end,
    -- }}}

    -- {{{ decode(body)
    decode = function(body)
        return {
            content     = body.content,
            stop_reason = body.stop_reason,
        }
    end,
    -- }}}

    headers = function(credential, asking)
        return string.format(
            "x-api-key: %s\nanthropic-version: %s\ncontent-type: application/json\n",
            credential, asking.version or "2023-06-01")
    end,
}
-- }}}

-- {{{ spoken_tool_calls(text)
-- Tool calls a model wrote as TEXT, lifted out and turned into real ones.
--
-- A tool call has never been anything but text. The model emits characters; a
-- harness watches for the agreed shape, pulls it out of the stream, and runs
-- it. Servers that support "native" tool calling are doing exactly this and
-- returning the result in a separate field -- the parsing has moved, not
-- vanished.
--
-- A model too small to have been trained on a particular server's tool syntax
-- still knows the shape from everything else it read, and writes it into its
-- answer. Refusing to look means throwing away a call the model correctly
-- decided to make, and showing the person a line of JSON as though it were
-- prose.
--
-- So both are read: the field if it is there, and the text if it is not.
--
-- The shapes seen in practice, all handled:
--     {"name": "x", "arguments": {...}}
--     {"name": "x", "parameters": {...}}
--     <tool_call>{"name": ...}</tool_call>
--     ```json\n{"name": ...}\n```
--     {"tool_call": {"name": ...}}
local function spoken_tool_calls(text, Json)
    if not text or text == "" then return nil, text end

    local found, cleaned = {}, text

    -- {{{ candidates
    -- Every balanced {...} in the text, outermost first. Brace counting rather
    -- than a pattern, because Lua patterns cannot match nesting and a tool
    -- call's arguments are themselves an object.
    local candidates = {}
    local depth, opened = 0, nil

    for index = 1, #text do
        local character = text:sub(index, index)
        if character == "{" then
            if depth == 0 then opened = index end
            depth = depth + 1
        elseif character == "}" then
            depth = depth - 1
            if depth == 0 and opened then
                table.insert(candidates, { from = opened, to = index })
                opened = nil
            elseif depth < 0 then
                depth = 0
            end
        end
    end
    -- }}}

    for _, span in ipairs(candidates) do
        local piece = text:sub(span.from, span.to)
        local ok, decoded = pcall(Json.decode, piece)

        if ok and type(decoded) == "table" then
            -- Some models wrap it one level deeper.
            local call = decoded.tool_call or decoded.function_call or decoded

            local name = call.name or (call["function"] and call["function"].name)
            local input = call.arguments or call.parameters or call.input
                       or (call["function"] and (call["function"].arguments
                                              or call["function"].parameters))

            if type(name) == "string" and name ~= "" then
                -- Arguments may arrive as a JSON string rather than an object.
                if type(input) == "string" then
                    local parsed_ok, parsed = pcall(Json.decode, input)
                    input = (parsed_ok and type(parsed) == "table") and parsed or {}
                end

                table.insert(found, { name = name,
                                      input = type(input) == "table" and input or {} })

                -- Lifted out of the prose, along with any wrapper around it.
                cleaned = cleaned:gsub(piece:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"), "", 1)
            end
        end
    end

    if #found == 0 then return nil, text end

    cleaned = cleaned
        :gsub("<tool_call>%s*</tool_call>", "")
        :gsub("```json%s*```", "")
        :gsub("```%s*```", "")
        :gsub("^%s+", ""):gsub("%s+$", "")

    return found, cleaned
end

Dialects.spoken_tool_calls = spoken_tool_calls
-- }}}

-- {{{ ollama
Dialects.ollama = {
    name = "ollama",

    -- {{{ encode(request, asking)
    -- Flatten the conversation into Ollama's message list.
    --
    -- The system prompt becomes the first message. Assistant turns carrying
    -- tool calls become an assistant message plus its tool_calls. A user turn
    -- that is a list of tool_result blocks becomes one "tool" message PER
    -- RESULT, in the order the calls were made -- because that order is the
    -- only thing left connecting a result to its call once the ids are gone.
    encode = function(request, asking)
        local messages = {}

        if request.system then
            table.insert(messages, { role = "system", content = request.system })
        end

        for _, message in ipairs(request.messages) do
            if type(message.content) == "string" then
                table.insert(messages,
                    { role = message.role, content = message.content })

            elseif message.role == "assistant" then
                local said, calls = {}, {}

                for _, block in ipairs(message.content) do
                    if block.type == "text" then
                        table.insert(said, block.text)
                    elseif block.type == "tool_use" then
                        table.insert(calls, {
                            ["function"] = {
                                name      = block.name,
                                arguments = block.input,
                            },
                        })
                    end
                end

                local turn = { role = "assistant",
                               content = table.concat(said, "\n") }
                if #calls > 0 then turn.tool_calls = calls end
                table.insert(messages, turn)

            else
                -- A user turn. Either plain content, or the tool results the
                -- loop packed into one message.
                local results = {}

                for _, block in ipairs(message.content) do
                    if block.type == "tool_result" then
                        table.insert(results, block)
                    end
                end

                if #results > 0 then
                    for _, result in ipairs(results) do
                        table.insert(messages, {
                            role    = "tool",
                            content = tostring(result.content),
                        })
                    end
                else
                    local said = {}
                    for _, block in ipairs(message.content) do
                        if block.type == "text" then
                            table.insert(said, block.text)
                        end
                    end
                    table.insert(messages,
                        { role = "user", content = table.concat(said, "\n") })
                end
            end
        end

        local tools = {}
        for _, tool in ipairs(request.tools or {}) do
            table.insert(tools, {
                type = "function",
                ["function"] = {
                    name        = tool.name,
                    description = tool.description,
                    parameters  = tool.input_schema,
                },
            })
        end

        return {
            model    = asking.model,
            messages = messages,
            tools    = #tools > 0 and tools or nil,
            -- One whole answer rather than a stream. A tool-calling turn is not
            -- read as it arrives, so streaming buys nothing and costs a parser.
            stream   = false,
            options  = { num_predict = asking.max_tokens or 8192 },
        }
    end,
    -- }}}

    -- {{{ decode(body)
    -- Back into content blocks, inventing the ids Ollama does not send.
    --
    -- The loop matches every tool_result to a tool_use by id, and Ollama's tool
    -- calls have none. Ids are minted here, in call order, and the ones going
    -- back out are dropped again by `encode` above -- so the id exists only
    -- inside neuron, which is exactly where it is needed.
    decode = function(body, Json)
        local message = body.message or {}
        local content = {}

        local said = message.content or ""
        local spoken = nil

        -- Only look in the text when the server reported no calls of its own.
        -- A server that parsed them has already removed them from the text, and
        -- looking again would find nothing or find something twice.
        if #(message.tool_calls or {}) == 0 and Json then
            spoken, said = spoken_tool_calls(said, Json)
        end

        if said and said ~= "" then
            table.insert(content, { type = "text", text = said })
        end

        for index, call in ipairs(spoken or {}) do
            table.insert(content, {
                type  = "tool_use",
                id    = string.format("spoken_%d_%d", os.time(), index),
                name  = call.name,
                input = call.input,
            })
        end

        for index, call in ipairs(message.tool_calls or {}) do
            local named = call["function"] or {}

            -- Arguments may arrive as an object or as a JSON string, depending
            -- on the model. A string here would reach Schema.route as a string
            -- and fail as "missing every required argument", which reads as the
            -- model being stupid rather than as a decoding problem.
            local arguments = named.arguments
            if type(arguments) == "string" then
                arguments = { __unparsed = arguments }
            end

            table.insert(content, {
                type  = "tool_use",
                id    = string.format("ollama_%d_%d", os.time(), index),
                name  = named.name,
                input = arguments or {},
            })
        end

        local calling = (message.tool_calls and #message.tool_calls > 0)
                     or (spoken and #spoken > 0)

        return {
            content     = content,
            stop_reason = calling and "tool_use" or (body.done_reason or "end_turn"),
        }
    end,
    -- }}}

    -- A local server wants no credential at all. Content type only.
    headers = function()
        return "content-type: application/json\n"
    end,
}
-- }}}

-- {{{ Dialects.of(name)
function Dialects.of(name)
    local dialect = Dialects[name]

    if not dialect then
        local known = {}
        for key, value in pairs(Dialects) do
            if type(value) == "table" and value.name then
                table.insert(known, key)
            end
        end
        table.sort(known)

        return nil, string.format(
            "'%s' is not a dialect neuron speaks.\n"
         .. "  It knows: %s.\n"
         .. "  A dialect is how one server's wire format is translated to and\n"
         .. "  from the shape the conversation loop uses. Adding a place to ask\n"
         .. "  means adding one of these, not editing the loop.",
            tostring(name), table.concat(known, ", "))
    end

    return dialect
end
-- }}}

return Dialects
