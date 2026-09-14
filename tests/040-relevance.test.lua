--------------------------------------------------------------------------------
-- tests/040-relevance.test.lua
--
-- The decay curve and the budget split, with time passed in rather than waited
-- for.
--
-- The budget cases are the ones that matter most. A split that is one over the
-- total produces a truncated prompt, and a prompt truncated at the end loses
-- whatever was most recent -- exactly the part that mattered. That failure does
-- not look like an arithmetic bug when it happens; it looks like a creature
-- that stopped noticing things.
--------------------------------------------------------------------------------

local NEURON = "/mnt/mtwo/games/azeroth-core/wow-chat-neuron"

local Load      = dofile(NEURON .. "/src/024-load.lua")
local Relevance = Load(NEURON .. "/src/039-memory/040-relevance.lua")

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

-- {{{ close(label, got, want, tolerance)
local function close(label, got, want, tolerance)
    if got and math.abs(got - want) <= (tolerance or 0.001) then
        passed = passed + 1
    else
        failed = failed + 1
        print(string.format("FAIL  %s\n        got  %s\n        want %s +/- %s",
            label, tostring(got), tostring(want), tostring(tolerance or 0.001)))
    end
end
-- }}}

-- {{{ the curve
close("a line just said is fully relevant",  Relevance.chatlog(100, 100),  1.0)
close("one half-life is halfway down",       Relevance.chatlog(100, 108),  0.5)
close("two half-lives is a quarter",         Relevance.chatlog(100, 116),  0.25)

-- The specified behaviour: faded, but not a corner where it stops existing.
local at_thirty = Relevance.chatlog(100, 130)
close("~30 seconds is cool",                 at_thirty, 0.074, 0.005)
check("and still above nothing",             at_thirty > 0,                true)

-- It approaches resting and never overshoots it, however long you wait.
check("never goes negative",  Relevance.chatlog(100, 100000) >= 0,          true)
check("never exceeds full",   Relevance.chatlog(100, 100) <= 1.0,           true)
-- }}}

-- {{{ any change, either direction, resets it
-- Nothing is deleted when relevance falls, so speaking after a long silence
-- puts the creature fully back into a conversation it still has every word of.
local heard = Relevance.chatlog(100, 128)       -- nearly cold
check("nearly cold before",   heard < 0.1,                                  true)
close("and full the moment anything is appended",
    Relevance.chatlog(128, 128),                                            1.0)
-- }}}

-- {{{ a clock running backwards is refused
local impossible, why = Relevance.chatlog(200, 100)
check("a future last-change is refused",     impossible,                    nil)
check("and says both readings",
    why:find("last change: 200", 1, true) ~= nil,                           true)
-- }}}

-- {{{ the other two stores do not cool
local hot  = Relevance.weigh({ chatlog_changed = 100 }, 100)
local cold = Relevance.weigh({ chatlog_changed = 100 }, 160)

close("chatlog is hot when just spoken",     hot.chatlog,                   1.0)
check("chatlog has cooled a minute later",   cold.chatlog < 0.01,           true)
check("the ring did not cool",               hot.ring,                      cold.ring)
check("the sheet did not cool",              hot.sheet,                     cold.sheet)

-- A conversation crowds the room out; it does not silence it.
check("the ring is present even mid-conversation", hot.ring > 0,            true)
check("the sheet is present even mid-conversation", hot.sheet > 0,          true)
-- }}}

-- {{{ the budget always sums to exactly the total
-- The case naive rounding gets wrong: three equal shares of 100.
local thirds = Relevance.budget({ a = 1, b = 1, c = 1 }, 100)
check("three equal shares sum to the total",
    thirds.a + thirds.b + thirds.c,                                         100)

-- Across a wide range of budgets and a lopsided split.
local lopsided = { chatlog = 1.0, ring = 0.6, sheet = 0.35 }
local exact = true
for total = 0, 400 do
    local given = Relevance.budget(lopsided, total)
    if given.chatlog + given.ring + given.sheet ~= total then exact = false end
end
check("every budget from 0 to 400 sums exactly",  exact,                    true)

-- Proportions are respected, not just the sum.
local hundred = Relevance.budget(lopsided, 100)
check("the hottest store gets the most",
    hundred.chatlog > hundred.ring and hundred.ring > hundred.sheet,        true)
close("and roughly its share",  hundred.chatlog, 51, 1)

-- A cold chatlog hands its room to the other two rather than wasting it.
local quiet = Relevance.budget({ chatlog = 0.01, ring = 0.6, sheet = 0.35 }, 100)
check("a cold conversation frees the room",
    quiet.ring + quiet.sheet,                                               99)
-- }}}

-- {{{ edges
local silent = Relevance.budget({ chatlog = 0, ring = 0, sheet = 0 }, 50)
check("everything silent allocates nothing",  silent.chatlog,               0)
check("and does not error",                   silent.sheet,                 0)

local nothing = Relevance.budget({ chatlog = 1, ring = 1 }, 0)
check("a zero budget allocates zero",         nothing.chatlog,              0)

check("a negative budget is refused",
    pcall(Relevance.budget, { a = 1 }, -10),                                false)
check("a negative relevance is refused",
    pcall(Relevance.budget, { a = -1, b = 1 }, 10),                         false)

-- Determinism: the same split twice puts the spare unit in the same place.
local first  = Relevance.budget({ a = 1, b = 1, c = 1 }, 100)
local second = Relevance.budget({ a = 1, b = 1, c = 1 }, 100)
check("the split is reproducible",  first.a == second.a and first.b == second.b,
                                                                            true)
-- }}}

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
