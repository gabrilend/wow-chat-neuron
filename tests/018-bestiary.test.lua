--------------------------------------------------------------------------------
-- tests/018-bestiary.test.lua
--
-- The creature-type enums and the bestiary's declaration.
--
-- The query itself needs MySQL and is not exercised. What is exercised is the
-- numbering, which is the part that fails silently: a wrong type number returns
-- beasts when somebody asked for undead, and the answer looks entirely
-- reasonable.
--------------------------------------------------------------------------------

local NEURON = "/mnt/mtwo/games/azeroth-core/wow-chat-neuron"

local Load     = dofile(NEURON .. "/src/024-load.lua")
local Types    = Load(NEURON .. "/src/017-creature-types.lua")
local Bestiary = Load(NEURON .. "/src/018-bestiary.lua")
local Registry = Load(NEURON .. "/src/045-toolbox/047-registry.lua")

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

-- {{{ the numbers, against the core's own header
-- source-beta/src/server/shared/SharedDefines.h:2620, verified 2026-09-04.
check("beast",        Types.kind.beast.id,          1)
check("undead",       Types.kind.undead.id,         6)
check("humanoid",     Types.kind.humanoid.id,       7)
check("gas cloud",    Types.kind.gas_cloud.id,     13)
check("thirteen types, no gaps",  #Types.kind.members,  13)

-- SharedDefines.h:2962. Note that rare (4) is numbered ABOVE world boss (3),
-- which is the game's ordering and not a difficulty ranking -- reading `id` as
-- "how hard" would put a rare above a raid boss.
check("normal",       Types.rank.normal.id,         0)
check("elite",        Types.rank.elite.id,          1)
check("world boss",   Types.rank.world_boss.id,     3)
check("rare",         Types.rank.rare.id,           4)
check("worth is the difficulty, not the id",
    Types.rank.world_boss.worth > Types.rank.rare.worth,               true)
-- }}}

-- {{{ index is not the game's number
check("index counts from one",   Types.kind.beast.index,      1)
check("id counts from one too, here",  Types.kind.beast.id,   1)
check("but read id, not index",  Types.kind.gas_cloud.index,  13)
-- }}}

-- {{{ fightable is this project's judgment, not the game's
-- creature_template holds tens of thousands of rows and most are quest props,
-- invisible triggers and scenery. A model handed the raw list spawns a squirrel.
check("undead can fight",         Types.kind.undead.fightable,        true)
check("a critter cannot",         Types.kind.critter.fightable,      false)
check("nor a totem",              Types.kind.totem.fightable,        false)
check("nor 'not specified'",      Types.kind.not_specified.fightable, false)

local fightable = 0
for _, kind in ipairs(Types.kind.members) do
    if kind.fightable then fightable = fightable + 1 end
end
check("eight of thirteen are worth fighting",  fightable,                    8)
-- }}}

-- {{{ by_id
check("finds a member by the game's number",  Types.by_id(Types.kind, 6),
                                              Types.kind.undead)
check("and a rank",  Types.by_id(Types.rank, 3),  Types.rank.world_boss)

local missing, why = Types.by_id(Types.kind, 99)
check("a number outside the set is refused",  missing,                     nil)
check("and lists every number the game uses",
    why:find("6=undead", 1, true) ~= nil,                                  true)
check("and says where to check",
    why:find("header this file names", 1, true) ~= nil,                          true)
-- }}}

-- {{{ the declaration
local operation, define_why = Registry.define(Bestiary.declaration, Bestiary)
check("it registers",            operation ~= nil,                         true)
if not operation then print(define_why) os.exit(1) end

check("it is a read",            operation.kind.name,                    "read")
check("so it needs no plan or apply",  operation.plan,                    nil)
check("and gets no --plan flag",
    Registry.usage(operation):find("--plan", 1, true),                     nil)
check("it works with the world down",  operation.hands[1].name,          "cold")
check("every parameter is optional",
    #operation.params, 5)

local required = 0
for _, parameter in ipairs(operation.params) do
    if parameter.required then required = required + 1 end
end
check("literally none is required",  required,                              0)
-- }}}

-- {{{ describing an empty answer
-- The message has to explain the filtering, or an empty result reads as an
-- empty database rather than as a narrow question.
local nothing = Bestiary.describe({}, { type = "undead", level = 12 })
check("an empty answer names what was asked",
    nothing:find("type undead", 1, true) ~= nil,                           true)
check("and at what level",
    nothing:find("at level 12", 1, true) ~= nil,                           true)
check("and explains that most of the table is scenery",
    nothing:find("scenery and quest triggers", 1, true) ~= nil,            true)
-- }}}

-- {{{ describing rows
local lines = Bestiary.describe({
    { entry = 1501, name = "Rotting Ghoul", minlevel = 10, maxlevel = 12,
      kind = "undead", rank = "normal", worth = 1 },
}, {})
check("a row shows its entry number",  lines:find("1501", 1, true) ~= nil,  true)
check("its name",       lines:find("Rotting Ghoul", 1, true) ~= nil,        true)
check("its level band", lines:find("10-12", 1, true) ~= nil,               true)
check("and its rank",   lines:find("normal", 1, true) ~= nil,              true)
-- }}}

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
