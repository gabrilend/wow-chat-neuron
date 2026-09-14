--------------------------------------------------------------------------------
-- 048-schema.lua
--
-- The registry, rendered as a tool list a model can be handed.
--
-- Nothing here is written by hand and nothing here is a second description of
-- an operation. Every field comes off the declaration that already serves the
-- command line, which is what makes the project's standing rule true rather
-- than aspirational: an operation cannot exist as a command without existing as
-- a tool, and there is no back door where a person reaches something a model
-- cannot.
--
-- The one transformation worth knowing about is that the four resolving
-- parameter types -- roster, place, items, receipt -- all become "string". A
-- model cannot hold a resolved roster and should not try; it says the words a
-- person would say, and coercion turns them into rows on the way in. The prose
-- attached to the parameter is therefore carrying all of the teaching, which is
-- why the registry refuses a parameter whose description is too short to say
-- anything.
--------------------------------------------------------------------------------

local here = debug.getinfo(1, "S").source:match("^@(.*/)")
local Load = dofile(here .. "../024-load.lua")

local Json = Load(here .. "../001-json.lua")

local Schema = {}

-- {{{ Schema.tool_name(operation_name) / Schema.operation_name(tool_name)
-- character.teleport <-> character_teleport
--
-- Tool names in the API are letters, digits and underscores, and an operation
-- name is subject.verb. The two therefore differ by exactly one substitution,
-- and it is applied in one place and reversed in one place. Written down here
-- rather than left in two call sites, because a mapping that lives only in code
-- is a mapping somebody reimplements slightly differently and then spends an
-- afternoon on.
function Schema.tool_name(operation_name)
    return (operation_name:gsub("%.", "_"))
end

function Schema.operation_name(tool_name)
    return (tool_name:gsub("_", "."))
end
-- }}}

-- {{{ describe(operation)
-- What a model reads when choosing between words.
--
-- The summary, plus two things a model cannot see from the schema alone and
-- must know before choosing: whether the word can be undone, and what it needs
-- to be running. Both change whether picking this word is reasonable right now,
-- and neither is expressible as a property of an argument.
local function describe(operation)
    local lines = { operation.summary }

    if operation.kind.name == "final" then
        table.insert(lines,
            "THIS CANNOT BE UNDONE. The receipt records what was destroyed and "
         .. "cannot restore it. Say plainly what you are about to do and get "
         .. "agreement before setting confirm.")
    elseif operation.kind.name == "change" then
        table.insert(lines,
            "This changes the world. It is reversible: the receipt captures "
         .. "what was there before, and character.return can put it back.")
    end

    local needs = {}
    for _, hand in ipairs(operation.hands) do
        if hand.needs ~= "nothing" then table.insert(needs, hand.needs) end
    end

    if #needs > 0 then
        table.insert(lines, "Reaches the world through: "
            .. table.concat(needs, " or ") .. ".")
    end

    return table.concat(lines, " ")
end
-- }}}

-- {{{ property(parameter)
local function property(parameter)
    local described = parameter.describes

    -- The type's own `accepts` text is deliberately NOT appended here.
    --
    -- It was, briefly, on the reasoning that JSON Schema has nowhere to put
    -- "this string is a query language". But a declaration's `describes` is
    -- written for exactly this reader -- it is the sentence a model reads when
    -- filling the argument in -- and a well-written one already says what the
    -- type accepts. Appending produced: "a comma-separated list of names, or a
    -- query like 'bots hunters 18-20'. Accepts a character name, a
    -- comma-separated list of names, or a query such as 'bots hunters 18-20'."
    -- The same sentence twice, which reads as carelessness and costs tokens.
    --
    -- The alternative would be to append only when the prose looks like it
    -- omitted something, which is a fallback protecting against a lazy
    -- description -- and the registry already refuses those. `accepts` stays
    -- for the catalogue and the command line, where nobody wrote prose.
    if parameter.default ~= nil then
        described = described .. " Defaults to " .. tostring(parameter.default) .. "."
    end

    local shape = { type = parameter.type.json, description = described }

    -- An array with no item type is a schema that permits anything, which is
    -- not what a list of names is. Stated rather than left open.
    if parameter.type.json == "array" then
        shape.items = { type = "string" }
    end

    return shape
end
-- }}}

-- {{{ Schema.tool(operation)
-- One entry in a tool list.
function Schema.tool(operation)
    local properties, required = {}, {}

    for _, parameter in ipairs(operation.params) do
        properties[parameter.name] = property(parameter)
        if parameter.required then table.insert(required, parameter.name) end
    end

    local input = {
        type       = "object",
        properties = properties,
    }

    -- Omitted rather than sent empty. An empty required array is legal and
    -- reads as a deliberate statement that nothing is required, which for an
    -- operation whose every argument is optional is true and worth saying --
    -- but for one with no parameters at all it is noise.
    if #required > 0 then
        input.required = required
    end

    return {
        name         = Schema.tool_name(operation.name),
        description  = describe(operation),
        input_schema = input,
    }
end
-- }}}

-- {{{ Schema.tools(registry, filter)
-- The whole set, or the part of it a caller will allow.
--
-- `filter` exists because the set handed to a model is not always the whole
-- registry. A conversation that must not destroy anything is one where the
-- final words are simply not in the list -- which is a much stronger guarantee
-- than asking a model not to use them, because a tool that is absent cannot be
-- called by mistake, by misunderstanding, or by persuasion.
function Schema.tools(registry, filter)
    local tools = {}

    for _, operation in ipairs(registry.ordered) do
        if not filter or filter(operation) then
            table.insert(tools, Schema.tool(operation))
        end
    end

    return tools
end
-- }}}

-- {{{ Schema.reads_only(operation) / Schema.no_final(operation)
-- Two filters worth having by name, because both describe a real posture rather
-- than an arbitrary subset.
function Schema.reads_only(operation)
    return operation.kind.name == "read"
end

function Schema.no_final(operation)
    return operation.kind.name ~= "final"
end
-- }}}

-- {{{ Schema.encode(registry, filter)
-- The JSON that goes in the request body.
function Schema.encode(registry, filter)
    local tools = Schema.tools(registry, filter)

    -- An empty Lua table is both an empty list and an empty object, and the
    -- encoder has to pick -- it picks {}. A tool list must be [], because a
    -- request carrying {} where an array belongs is rejected by the API rather
    -- than treated as "no tools". Json.array marks the table itself as a
    -- list, so it stays one when it is empty -- which is the same guarantee
    -- the old EMPTY_ARRAY sentinel gave, without needing a caller to notice
    -- the list came out empty and swap in a different value.
    if #tools == 0 then
        return Json.encode(Json.array(), "  ")
    end

    return Json.encode(tools, "  ")
end
-- }}}

-- {{{ Schema.route(registry, tool_use)
-- A model's tool_use block, turned back into an operation and its arguments.
--
-- The other half of the boundary. A tool name that is not a real operation ends
-- that request, so the refusal carries what would have worked -- the registry's
-- own near-match message, which is the only thing telling a model what exists.
function Schema.route(registry, tool_use)
    local name = Schema.operation_name(tool_use.name or "")

    local operation, why = registry.of(name)
    if not operation then
        return nil, why
    end

    local arguments = tool_use.input or {}

    -- A required parameter the model left out is caught here rather than inside
    -- the operation, so the message can name the parameter and its description
    -- -- which is the text the model already had and evidently did not act on,
    -- and repeating it is the most useful thing to say.
    for _, parameter in ipairs(operation.params) do
        if parameter.required and arguments[parameter.name] == nil then
            return nil, string.format(
                "%s needs '%s' and it was not given.\n  %s",
                operation.name, parameter.name, parameter.describes)
        end
    end

    return operation, arguments
end
-- }}}

return Schema
