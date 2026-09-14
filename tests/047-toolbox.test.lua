--------------------------------------------------------------------------------
-- tests/047-toolbox.test.lua
--
-- The registry and the tool schema, against the three operations that exist.
--
-- These are the two halves of the project's standing rule -- an operation
-- cannot exist as a command without existing as a tool -- and the rule is only
-- true if both halves come off the same declaration. Most of what follows
-- checks that a declaration which would produce a bad tool is refused when it
-- is registered, rather than producing a bad tool.
--------------------------------------------------------------------------------

local NEURON = "/mnt/mtwo/games/azeroth-core/wow-chat-neuron"

local Load     = dofile(NEURON .. "/src/024-load.lua")
local Registry = Load(NEURON .. "/src/045-toolbox/047-registry.lua")
local Schema   = Load(NEURON .. "/src/045-toolbox/048-schema.lua")
local Json     = Load(NEURON .. "/src/001-json.lua")

local passed, failed = 0, 0

-- {{{ check
local function check(label, got, want)
    if got == want then passed = passed + 1 else
        failed = failed + 1
        print(string.format("FAIL  %s\n        got  %s\n        want %s",
            label, tostring(got), tostring(want)))
    end
end
-- }}}

-- {{{ a well-formed declaration, to vary from
local function declaration(changes)
    local base = {
        name    = "world.example",
        summary = "An operation that exists only in this test.",
        kind    = "change",
        hands   = { "cold" },
        params  = {
            { name = "roster", type = "roster", required = true,
              describes = "Who it acts on: a name, a list, or a query." },
        },
    }
    for key, value in pairs(changes or {}) do base[key] = value end
    return base
end

local WORKS = { plan = function() end, apply = function() end,
                run = function() end }
-- }}}

local registry, load_why = Registry.load(NEURON)
check("the real registry loads",  registry ~= nil,                          true)
if not registry then print(load_why) os.exit(1) end

-- {{{ what is registered
-- Eight, one of which is temporary: world.announce exists to prove the pipeline
-- end to end and is meant to be deleted. When it goes, this becomes seven.
check("eight operations",                       #registry.ordered,          8)

-- NOTHING IRREVERSIBLE IS IN A VOCABULARY.
--
-- character.retire used to be `final` -- thirty-nine DELETE statements and a
-- receipt that could say what was destroyed but not rebuild it. It is the
-- game's own deleted queue now, and the permanent erase is `character.purge`
-- in 015-retire.lua, which is in no vocabulary and is reached from the command
-- line only. Something that cannot be undone should need the sort of
-- deliberation a conversation does not have.
check("no word a model can say is irreversible",
    (function()
        for _, op in ipairs(registry.ordered) do
            if op.kind.name == "final" then return op.name end
        end
        return "none"
    end)(),                                                              "none")

-- memory.forget is the odd one: the only lever that acts on the conversation
-- rather than on the world, and the only `internal` kind.
check("one of them is internal",
    (function()
        local found = 0
        for _, op in ipairs(registry.ordered) do
            if op.kind.name == "internal" then found = found + 1 end
        end
        return found
    end)(),                                                                  1)

check("and it is told which conversation it is in",
    registry.by_name["memory.forget"].needs_conversation,                 true)
check("one of them is the temporary test lever",
    registry.of("world.announce").summary:find("TEMPORARY", 1, true) ~= nil, true)
check("of which one is a read",
    registry.of("world.creatures").kind.name,                              "read")
check("and one creates something",
    registry.of("world.spawn").kind.name,                                "change")
check("sorted by subject then verb",            registry.ordered[1].name,  "character.restore")
check("looked up by name",                      registry.of("character.teleport").name,
                                                "character.teleport")
check("the subject is what is acted on",        registry.ordered[1].subject, "character")

-- Hands and kinds arrive as strings and are members by the time anything reads
-- them, so routing compares by identity.
check("hands are enum members",
    Registry.Hands.holds(registry.of("character.teleport").hands[1]),       true)
check("kind is an enum member",
    Registry.Kinds.holds(registry.of("character.retire").kind),             true)
check("retire is reversible now",
    registry.of("character.retire").kind.name,                          "change")
check("and restoring is its inverse",
    registry.of("character.restore").kind.name,                         "change")
check("teleport is change", registry.of("character.teleport").kind.name,    "change")
-- }}}

-- {{{ an unknown word carries what would have worked
local missing, why = registry.of("character.teleprot")
check("an unknown operation is refused",  missing,                          nil)
check("near words about the same subject are offered",
    why:find("Words about character", 1, true) ~= nil,                      true)
check("and the whole set is listed",
    why:find("character.retire, character.return", 1, true) ~= nil,         true)
-- }}}

-- {{{ usage is built, not written
check("usage comes off the declaration",
    Registry.usage(registry.of("character.teleport")),
    "neuron teleport --roster <rost> --place <plac> [--plan]")
check("optional parameters are bracketed, --plan is added by kind",
    Registry.usage(registry.of("character.retire")),
    "neuron retire --roster <rost> [--plan]")
-- }}}

-- {{{ declarations that would make a bad tool are refused
check("a name that is not subject.verb",
    Registry.define(declaration{ name = "teleport" }, WORKS),               nil)
check("an unknown hand",
    Registry.define(declaration{ hands = { "res" } }, WORKS),               nil)
check("no hands at all",
    Registry.define(declaration{ hands = {} }, WORKS),                      nil)
check("an unknown kind",
    Registry.define(declaration{ kind = "destructive" }, WORKS),            nil)
check("an unknown parameter type",
    Registry.define(declaration{ params = { { name = "x", type = "colour",
        required = true, describes = "some colour or other" } } }, WORKS),  nil)
check("two parameters with one name",
    Registry.define(declaration{ params = {
        { name = "x", type = "string", describes = "the first one here" },
        { name = "x", type = "string", describes = "the second one here" } } },
        WORKS),                                                             nil)
check("no summary",
    Registry.define(declaration{ summary = "moves" }, WORKS),               nil)

-- A parameter with no prose is a parameter a model cannot choose.
local terse, terse_why = Registry.define(declaration{ params = {
    { name = "roster", type = "roster", required = true, describes = "who" } } },
    WORKS)
check("a description too short to teach anything",  terse,                  nil)
check("and says what the description is for",
    terse_why:find("ONLY thing that can teach it", 1, true) ~= nil,         true)

-- The kind decides which functions must exist, which is what makes it a switch.
check("a change with no apply",
    Registry.define(declaration(), { plan = function() end }),              nil)
check("a read with no run",
    Registry.define(declaration{ kind = "read" }, { plan = function() end }), nil)
check("a read needs no plan or apply",
    Registry.define(declaration{ kind = "read" }, WORKS) ~= nil,            true)
-- }}}

-- {{{ the confirmation gate on anything final
local ungated, ungated_why = Registry.define(declaration{ kind = "final" }, WORKS)
check("a final operation with no confirm is refused",  ungated,             nil)
check("and says why the gate exists",
    ungated_why:find("in one step", 1, true) ~= nil,                        true)

-- Required would be worse than absent: a model fills it in on the first attempt.
local decorative, decorative_why = Registry.define(declaration{ kind = "final",
    params = {
        { name = "roster", type = "roster", required = true,
          describes = "Who it acts on: a name, a list, or a query." },
        { name = "confirm", type = "boolean", required = true,
          describes = "Confirm that this cannot be undone." } } }, WORKS)
check("a REQUIRED confirm is refused too",  decorative,                     nil)
check("and says it would be decorative",
    decorative_why:find("decorative", 1, true) ~= nil,                      true)
-- }}}

-- {{{ the schema
local teleport = Schema.tool(registry.of("character.teleport"))

check("the dot becomes an underscore",  teleport.name,      "character_teleport")
check("and reverses",  Schema.operation_name("character_teleport"), "character.teleport")

-- The collapse that makes one declaration serve both surfaces: a model cannot
-- hold a resolved roster, so it says the words a person would say.
check("a roster is a string to a model",
    teleport.input_schema.properties.roster.type,                           "string")
check("a place is a string to a model",
    teleport.input_schema.properties.place.type,                            "string")
check("required parameters are listed",
    #teleport.input_schema.required,                                        2)

-- The description carries what the schema cannot express.
check("the description says it is reversible",
    teleport.description:find("reversible", 1, true) ~= nil,                true)
check("and what it needs running",
    teleport.description:find("worldserver or database", 1, true) ~= nil,   true)

-- The capitals are still generated for `final` words; there is simply no
-- longer one in a vocabulary to generate them for. Checked against a
-- declaration built here rather than against a registered word, so the schema
-- keeps saying it if one ever comes back.
local made_up = Registry.define({
    name = "test.destroy", summary = "Erase something forever, with no undo.",
    kind = "final", hands = { "cold" },
    params = { { name = "target", type = "string", required = true,
                 describes = "What to erase." },
               -- Every `final` operation must offer one. The registry refuses
               -- the declaration otherwise, which is itself worth having a
               -- word about: the parameter existing in the schema is what
               -- stops a model reaching an irreversible word in one step.
               { name = "confirm", type = "boolean", required = false,
                 describes = "Say so out loud." } },
}, { plan = function() end, apply = function() end })

check("a final word must offer a way to confirm it",
    (Registry.define({ name = "test.nogate", summary = "No gate at all here.",
        kind = "final", hands = { "cold" },
        params = { { name = "x", type = "string", required = true,
                     describes = "Anything." } } },
        { plan = function() end, apply = function() end })),            nil)

check("an irreversible word says so in capitals",
    Schema.tool(made_up).description:find("CANNOT BE UNDONE", 1, true) ~= nil,
                                                                          true)

local retire = Schema.tool(registry.of("character.retire"))
check("retiring says the queue can be undone",
    retire.description:find("reversible", 1, true) ~= nil,                true)

-- The declaration's own prose, not the type's, and not both.
check("the description is not doubled",
    teleport.input_schema.properties.roster.description,
    "Who to move: a name, a comma-separated list of names, or a query like 'bots hunters 18-20'.")
-- }}}

-- {{{ filters remove a word rather than forbid it
-- A tool that is absent cannot be called by mistake, by misunderstanding, or by
-- persuasion, which is a much stronger guarantee than asking a model not to.
-- Nothing to drop any more, which is the point: the filter used to be the
-- thing standing between a model and an unrecoverable delete, and now the
-- vocabulary does not contain one.
check("no_final has nothing left to drop",
    #Schema.tools(registry, Schema.no_final),          #registry.ordered)
check("reads_only keeps only the read",
    #Schema.tools(registry, Schema.reads_only),                             1)

-- An empty Lua table is both an empty list and an empty object. A tool list
-- must encode as [], or the request is rejected rather than read as "no tools".
--
-- A filter matching nothing is not a mistake: handing a model an empty tool list
-- is how you ask it a question it must answer in words.
check("an empty tool list encodes as an array",
    Schema.encode(registry, function() return false end),                   "[]")
-- }}}

-- {{{ routing a tool_use back
local operation, arguments = Schema.route(registry,
    { name = "character_teleport", input = { roster = "Grast", place = "ratchet" } })
check("a tool_use finds its operation",  operation.name,     "character.teleport")
check("with its arguments",              arguments.place,    "ratchet")

local _, absent = Schema.route(registry,
    { name = "character_teleport", input = { roster = "Grast" } })
check("a missing required argument is caught before the operation runs",
    absent:find("needs 'place'", 1, true) ~= nil,                           true)
check("and repeats the description the model already had",
    absent:find("a named location such as 'ratchet'", 1, true) ~= nil,      true)

local _, no_such = Schema.route(registry, { name = "character_obliterate" })
check("an invented tool name is refused with the real set",
    no_such:find("Everything neuron knows", 1, true) ~= nil,                true)
-- }}}

-- {{{ the indent bug this file found
-- string.rep(2, depth) is "22", so a number indent produces a document indented
-- with digits -- still valid JSON, still wrong, and invisible at a glance.
check("a number indent is refused",
    pcall(Json.encode, { a = 1 }, 2),                                       false)
check("a string indent works",
    Json.encode({ 1, 2 }, "  "),                                            "[\n  1,\n  2\n]")
check("and no indent is still compact",  Json.encode({ 1, 2 }),             "[1,2]")
-- }}}

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
