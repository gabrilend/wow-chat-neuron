--------------------------------------------------------------------------------
-- 056-spoken-calls.test.lua
--
-- The tool-call examples in the system prompt must be calls the parser accepts.
--
-- WHY THIS TEST EXISTS: the loop teaches a small model how to write a tool call
-- by showing it four worked examples. If those examples are a shape
-- 056-dialects.lua does not lift out of prose, the instruction is worse than
-- silence -- the model follows it exactly and the call is read as a sentence.
-- Two files that must agree, so the agreement is checked rather than assumed.
--------------------------------------------------------------------------------

local ROOT     = "/mnt/mtwo/games/azeroth-core/wow-chat-neuron"
local Json     = dofile(ROOT .. "/src/001-json.lua")
local Dialects = dofile(ROOT .. "/src/056-dialects.lua")
local Loop     = dofile(ROOT .. "/src/051-loop.lua")

local passed, failed = 0, 0

-- {{{ check(what, got, want)
local function check(what, got, want)
    if got == want then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL  " .. what)
        print("        got  " .. tostring(got))
        print("        want " .. tostring(want))
    end
end
-- }}}

-- {{{ every example in the lesson is lifted back out
-- Pulled from the prompt text itself rather than retyped here. Retyping them
-- would make this test pass while the lesson said something else.
local examples = {}
for line in Loop.HOW_TO_CALL:gmatch("[^\n]+") do
    if line:match('^%s*{%s*"name"') then table.insert(examples, line) end
end

check("the lesson has four worked examples",         #examples,             4)

for _, example in ipairs(examples) do
    local calls = Dialects.spoken_tool_calls(example, Json)
    local name  = example:match('"name":%s*"([^"]+)"')

    check("'" .. tostring(name) .. "' is read as a call",
        calls ~= nil and #calls == 1,                                     true)

    if calls and calls[1] then
        -- { name, input }. The `type = "tool_use"` wrapper is added by the
        -- dialect that assembled the response, not here -- this function's job
        -- ends at recognising the shape.
        check("  and keeps its name",       calls[1].name,               name)
        check("  with an arguments table",  type(calls[1].input),      "table")
    end
end
-- }}}

-- {{{ the arguments survive, with their types
local several = 'I will do this now. {"name": "world_spawn", "arguments": '
             .. '{"creature": 299, "place": "goldshire", "count": 3}}'

local calls = Dialects.spoken_tool_calls(several, Json)

check("a call inside a sentence is still found", calls ~= nil and #calls, 1)
check("a number stays a number",   type(calls[1].input.creature),    "number")
check("with its value",                  calls[1].input.creature,         299)
check("a string stays a string",   type(calls[1].input.place),       "string")
check("with its value",                  calls[1].input.place,     "goldshire")
-- }}}

-- {{{ prose alone is not a call
-- The exact sentence a small model wrote instead of calling anything. It must
-- NOT be mistaken for a call -- inventing one from prose would be worse than
-- missing it, because it would run something nobody asked for.
local prose = "I will change the timeout to 15 seconds."

check("a sentence about acting is not an act",
    Dialects.spoken_tool_calls(prose, Json),                             nil)
-- }}}

-- {{{ the lesson is sent only where it is needed
-- A model with a real tool protocol should use it; teaching it a text form
-- invites prose that merely looks like a call.
check("the configuration window always gets it",
    Loop.local_model_answers({ asking = {} }, { vocabulary = "asking" }), true)

check("a world window with no local model does not",
    Loop.local_model_answers({ asking = { model = "x" } },
                             { vocabulary = "world" }),                false)

check("a world window told to use the bench does",
    Loop.local_model_answers({ asking = { use = "bench", bench = { model = "y" } } },
                             { vocabulary = "world" }),                 true)
-- }}}

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
