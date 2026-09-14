--------------------------------------------------------------------------------
-- tests/034-mechanism.test.lua
--
-- The routing layer, exercised without a deployment.
--
-- Everything here runs with no database and no worldserver, because everything
-- here is about the shape of the routing rather than about reaching anything.
-- The parts that need a live world -- performing an actual cold write, actually
-- installing a resident script -- are not testable this way and are not
-- pretended to be.
--------------------------------------------------------------------------------

local NEURON = "/mnt/mtwo/games/azeroth-core/wow-chat-neuron"

local Load      = dofile(NEURON .. "/src/024-load.lua")
local Mechanism = Load(NEURON .. "/src/033-mechanisms/034-mechanism.lua")
local Hands     = Mechanism.Hands
local Refusals  = Mechanism.Refusals

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

local MECHANISMS = Mechanism.dispatch(NEURON)

-- {{{ the table is complete
-- A hand with no mechanism is a routing hole that would otherwise be found on
-- the day somebody first declares an operation preferring it.
for _, hand in ipairs(Hands.members) do
    check("every hand routes: " .. hand.name,
        MECHANISMS[hand] ~= nil,                                     true)
    check("and routes to itself: " .. hand.name,
        MECHANISMS[hand].hand,                                       hand)
end
-- }}}

-- {{{ routing is by identity, not by name
-- The property the whole enum layer exists for: a string that spells a hand
-- correctly still does not open the door.
check("a string does not index the table",  MECHANISMS["cold"],      nil)

local impostor = { name = "cold", carries = { "sql", "binds", "database" } }
check("an impostor does not index it",      MECHANISMS[impostor],    nil)
-- }}}

-- {{{ a step is checked against its own hand's needs
local incomplete = MECHANISMS[Hands.cold].perform({},
    { describes = "move Grast to Ratchet" })

check("an incomplete step is refused",      incomplete.ok,           false)
check("and refused as an argument fault",   incomplete.refusal,      Refusals.argument)
check("naming every missing field",
    incomplete.why:find("sql, binds, database", 1, true) ~= nil,     true)
check("and quoting the step's description",
    incomplete.why:find("move Grast to Ratchet", 1, true) ~= nil,    true)

-- The same step, routed to a hand that wants different fields, is fine there.
local live_step = { command = "server info", describes = "ask the world its version" }
check("a live step needs only a command",
    MECHANISMS[Hands.live].validate(live_step),                      true)
check("but is incomplete as a cold step",
    MECHANISMS[Hands.cold].validate(live_step),                      nil)
-- }}}

-- {{{ empty binds are present, not absent
-- A statement with no placeholders binds an empty table. Testing truthiness
-- rather than presence would call that missing, and every parameterless
-- statement in the project would be refused.
local no_placeholders = { sql = "DELETE FROM x", binds = {},
                          database = "acore_characters", describes = "clear x" }
check("an empty binds table counts as given",
    MECHANISMS[Hands.cold].validate(no_placeholders),                true)
-- }}}

-- {{{ the none hand
local answered = MECHANISMS[Hands.none].perform({},
    { describes = "print the catalogue" })
check("the none hand succeeds",             answered.ok,             true)
check("and changed nothing",                answered.changed,        0)

local up, reason = MECHANISMS[Hands.none].probe({})
check("the none hand is always up",         up,                      true)
check("with a reason",                      reason,                  "up")
-- }}}

-- {{{ a raising hand still returns a value
-- One malformed step must not destroy the receipt for every step that already
-- worked, so a hand that throws is caught and turned into an outcome.
local exploding = Mechanism.define {
    hand      = Hands.none,
    probe     = function() return true, "up", "" end,
    describes = function() return "explode" end,
    perform   = function() error("the hand fell off") end,
}

local caught = exploding.perform({}, { describes = "step forty" })
check("a raising hand returns a value",     caught.ok,               false)
check("marked as a refusal",                caught.refusal,          Refusals.refused)
check("carrying the original error",
    caught.why:find("the hand fell off", 1, true) ~= nil,            true)
check("and which step caused it",
    caught.why:find("step forty", 1, true) ~= nil,                   true)
-- }}}

-- {{{ definition-time refusals
check("a mechanism keyed on a string is refused",
    pcall(Mechanism.define, { hand = "cold", probe = print,
                              perform = print, describes = print }),  false)
check("a mechanism missing perform is refused",
    pcall(Mechanism.define, { hand = Hands.none, probe = print,
                              describes = print }),                   false)
check("failed() refuses a non-member refusal",
    pcall(Mechanism.failed, "argument", "why"),                       false)
-- }}}

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
