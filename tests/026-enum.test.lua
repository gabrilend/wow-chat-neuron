--------------------------------------------------------------------------------
-- tests/026-enum.test.lua
--
-- The properties the enum design rests on, each stated as a test because each
-- one is invisible when it breaks.
--
-- An enum whose members stopped being unique still works: names still read
-- correctly, printing still looks right, and every comparison quietly returns
-- false. The dispatch table finds nothing and the failure says "no mechanism
-- for this hand" while the hand is plainly right there. So these are not
-- coverage; they are the only place that failure is visible.
--------------------------------------------------------------------------------

local NEURON = "/mnt/mtwo/games/azeroth-core/wow-chat-neuron"

local Load     = dofile(NEURON .. "/src/024-load.lua")
local Enum     = Load(NEURON .. "/src/025-enums/026-enum.lua")
local Hands    = Load(NEURON .. "/src/025-enums/027-hands.lua")
local Kinds    = Load(NEURON .. "/src/025-enums/028-kinds.lua")
local Slots    = Load(NEURON .. "/src/025-enums/030-slots.lua")
local Classes  = Load(NEURON .. "/src/025-enums/032-classes.lua")

local passed, failed = 0, 0

-- {{{ check(label, got, want)
local function check(label, got, want)
    if got == want then
        passed = passed + 1
    else
        failed = failed + 1
        print(string.format("FAIL  %s\n        got  %s\n        want %s",
            label, tostring(got), tostring(want)))
    end
end
-- }}}

-- {{{ identity
-- The whole design. A member equals itself and equals nothing else.
check("a member equals itself",           Hands.cold == Hands.cold,  true)
check("a member is not its own name",     Hands.cold == "cold",      false)
check("two members differ",               Hands.cold == Hands.live,  false)

-- The case that motivated the loader: a second load must not mint new members.
local second = Load(NEURON .. "/src/025-enums/027-hands.lua")
check("a second load is the same enum",   second == Hands,           true)
check("a second load's member is ours",   second.cold == Hands.cold, true)

-- And through a path spelled differently, which is how a file inside a
-- subdirectory reaches one outside it.
local dotted = Load(NEURON .. "/src/025-enums/../025-enums/027-hands.lua")
check("a `..` path is the same enum",     dotted == Hands,           true)
-- }}}

-- {{{ knowing which one was ours
check("holds its own member",             Hands.holds(Hands.cold),   true)
check("does not hold a string",           Hands.holds("cold"),       false)
check("does not hold nil",                Hands.holds(nil),          false)
check("does not hold a number",           Hands.holds(4),            false)

-- The case a string comparison cannot catch at all: a member from a different
-- enum. Both are tables, both have a `name`, and only the back-reference tells
-- them apart.
check("does not hold another enum's",     Hands.holds(Kinds.read),   false)
check("the other enum holds it",          Kinds.holds(Kinds.read),   true)

-- A hand-built impostor carrying the right name and shape.
local impostor = { name = "cold", index = 1, enum = { name = "Hands" } }
check("does not hold an impostor",        Hands.holds(impostor),     false)
check("an impostor is not the member",    impostor == Hands.cold,    false)
-- }}}

-- {{{ the boundary crossing
check("of resolves a name",               Hands.of("cold"),          Hands.cold)
check("of is case-sensitive",             Hands.of("Cold"),          nil)
check("of refuses an unknown name",       Hands.of("warm"),          nil)
check("of refuses a number",              Hands.of(7),               nil)
check("of refuses a member",              Hands.of(Hands.cold),      nil)

local _, near = Hands.of("res")
check("a near miss is named",
    near:find("resident", 1, true) ~= nil,                           true)

local _, unrelated = Hands.of("warm")
check("an unrelated name gets the full set",
    unrelated:find("cold, live, resident, none", 1, true) ~= nil,    true)

local _, wrong_type = Hands.of(7)
check("a wrong type is named as one",
    wrong_type:find("got a number", 1, true) ~= nil,                 true)
-- }}}

-- {{{ immutability
-- A member whose name can be reassigned is a member that can be made to lie.
check("a member refuses a new field",
    pcall(function() Hands.cold.colour = "blue" end),                false)
check("a member refuses to be renamed",
    pcall(function() Hands.cold.name = "warm" end),                  false)
check("the enum refuses a new member",
    pcall(function() Hands.warm = {} end),                           false)
check("the metatable cannot be replaced",
    pcall(function() setmetatable(Hands.cold, {}) end),              false)
check("the member survived all that",     Hands.cold.name,           "cold")
-- }}}

-- {{{ the trip back out to text
check("name_of returns the name",         Enum.name_of(Hands.live),  "live")
check("tostring returns the name",        tostring(Hands.live),      "live")
-- The trap this guards: a member is an EMPTY proxy table, so handing one
-- straight to a JSON encoder produces `{}` rather than `"live"`, silently.
check("name_of refuses a plain string",
    pcall(Enum.name_of, "live"),                                     false)
check("name_of refuses a bare table",
    pcall(Enum.name_of, {}),                                         false)
-- }}}

-- {{{ ordering and per-member data
check("members are ordered",              Hands.members[1],          Hands.cold)
check("index is position",                Hands.resident.index,      3)
check("names lists in order",
    table.concat(Hands.names(), ","),     "cold,live,resident,none")

-- Where the game's numbering and the enum's ordering disagree, reading the
-- wrong one is silent and wrong. Slots happen to line up off-by-one; classes
-- have a real gap at 10.
check("a slot carries the game's number", Slots.mainhand.slot,       15)
check("slot index is NOT the slot",       Slots.mainhand.index,      16)
check("a class carries the game's id",    Classes.druid.id,          11)
check("class index is NOT the id",        Classes.druid.index,       10)
check("the class gap is real",            #Classes.members,          10)
-- }}}

-- {{{ definition-time refusals
check("an enum with no members is refused",
    pcall(Enum.define, "Empty", {}),                                 false)
check("a duplicate member name is refused",
    pcall(Enum.define, "Twice", { {"a"}, {"a"} }),                    false)
check("a nameless member is refused",
    pcall(Enum.define, "Nameless", { {summary = "x"} }),             false)
-- }}}

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
