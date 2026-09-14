--------------------------------------------------------------------------------
-- 034-mechanism.lua
--
-- One hand, wearing a shape all four share, plus the table that routes to them.
--
-- Before this file, each command in the command line reached for its hand by
-- name and called it in that hand's own idiom: the cold hand wants a database,
-- a statement and a list of values; the live hand wants one string of command
-- text; the resident hand did not exist. Three shapes meant every new operation
-- added a fourth place that had to know all of them.
--
-- A mechanism gives all four one doorway, so the dispatcher can do this and
-- never learn which hand it got:
--
--     MECHANISMS[step.hand].perform(handle, step)
--
-- One index into a table keyed on enum members. Not a chain of comparisons, and
-- not keyed on a string that could be a near-miss spelling -- a spelling that
-- was not a real hand was refused at the edge where text became a member, and
-- never reached here.
--
-- Nothing in this file reimplements a hand. 002-cold-hand.lua and
-- 003-live-hand.lua work and have been run against a live world; these are
-- doorways onto them, not rewrites of them.
--------------------------------------------------------------------------------

local here = debug.getinfo(1, "S").source:match("^@(.*/)")
local Load = dofile(here .. "../024-load.lua")

local Hands    = Load(here .. "../025-enums/027-hands.lua")
local Refusals = Load(here .. "../025-enums/029-refusals.lua")

local Mechanism = {}

Mechanism.Hands    = Hands
Mechanism.Refusals = Refusals

-- {{{ Mechanism.done(changed, detail)
-- A step that happened. `changed` is how many rows or things moved -- zero is a
-- real answer and not a failure, since a write that affected nothing usually
-- means the world was already the way it was being asked to be.
function Mechanism.done(changed, detail)
    return { ok = true, changed = changed or 0, detail = detail or "" }
end
-- }}}

-- {{{ Mechanism.failed(refusal, why)
-- A step that did not happen, as a VALUE.
--
-- Nothing in a mechanism raises. An operation walking forty steps needs the
-- thirty-ninth failing to be something it can write into a receipt, not
-- something that unwinds the stack straight past the receipt writer and leaves
-- no record that thirty-eight of them succeeded.
function Mechanism.failed(refusal, why)
    if not Refusals.holds(refusal) then
        error("Mechanism.failed: the first argument must be a Refusals member, "
           .. "so that a caller can branch on the kind of failure without "
           .. "reading the sentence. Got: " .. tostring(refusal), 2)
    end
    return { ok = false, refusal = refusal, why = why }
end
-- }}}

-- {{{ Mechanism.define(specification)
-- Build one mechanism, refusing anything half-written.
--
-- The refusal is at load time on purpose. A fourth hand missing its `perform`
-- would otherwise be discovered at the moment somebody declares an operation
-- preferring it, which is both much later and much further from the mistake.
function Mechanism.define(specification)
    local hand = specification.hand

    if not Hands.holds(hand) then
        error("Mechanism.define: `hand` must be a Hands member. A mechanism "
           .. "keyed on a string cannot be looked up by a step carrying a "
           .. "member, which is the only way steps carry hands. Got: "
           .. tostring(hand), 2)
    end

    for _, required in ipairs({ "probe", "perform", "describes" }) do
        if type(specification[required]) ~= "function" then
            error(string.format(
                "Mechanism.define(%s): missing `%s`.\n"
             .. "  Every mechanism supplies probe (is this hand up), perform\n"
             .. "  (do the step), and describes (one line a person reads before\n"
             .. "  agreeing to it). A mechanism without all three cannot be\n"
             .. "  routed to generically, which is the entire point of having\n"
             .. "  a shape.", tostring(hand), required), 2)
        end
    end

    -- {{{ validate(step)
    -- Does this step carry what its hand needs?
    --
    -- Read off the hand enum's `carries` list rather than written again here,
    -- so the answer to "what does a cold step need" lives in exactly one place
    -- and the mechanism cannot drift from the enum that describes it.
    --
    -- This runs before anything is attempted. A cold step with no sql and a
    -- live step with no command are both programming mistakes in an operation,
    -- and they should surface while a plan is being built rather than halfway
    -- through applying one to forty characters.
    local function validate(step)
        local missing = {}

        for _, field in ipairs(hand.carries) do
            -- `binds` may legitimately be an empty table for a statement with
            -- no placeholders, so presence is the test, not truthiness.
            if step[field] == nil then table.insert(missing, field) end
        end

        if #missing == 0 then return true end

        return nil, string.format(
            "a %s step is missing: %s\n"
         .. "  A %s step must carry %s. This is a mistake in the operation that\n"
         .. "  built the step, not in the arguments somebody supplied -- the\n"
         .. "  step was constructed without a field its own hand requires.\n"
         .. "  The step describes itself as: %s",
            tostring(hand), table.concat(missing, ", "),
            tostring(hand), table.concat(hand.carries, ", "),
            step.describes or "(no description)")
    end
    -- }}}

    return {
        hand      = hand,
        probe     = specification.probe,
        describes = specification.describes,
        validate  = validate,

        -- {{{ perform(handle, step)
        -- Validate, then do it. Never raises.
        perform = function(handle, step)
            local ok, why = validate(step)
            if not ok then
                return Mechanism.failed(Refusals.argument, why)
            end

            local succeeded, outcome = pcall(specification.perform, handle, step)

            if not succeeded then
                -- A hand that raised is a bug in the hand, and it must still
                -- arrive back as a value -- otherwise one malformed step
                -- destroys the receipt for every step that already worked.
                return Mechanism.failed(Refusals.refused, string.format(
                    "the %s hand raised while performing a step.\n"
                 .. "  %s\n"
                 .. "  This is a fault in the hand rather than in the request.\n"
                 .. "  The step that caused it describes itself as: %s",
                    tostring(hand), tostring(outcome),
                    step.describes or "(no description)"))
            end

            return outcome
        end,
        -- }}}
    }
end
-- }}}

-- {{{ Mechanism.dispatch(neuron_root)
-- The routing table: every Hands member to its mechanism.
--
-- Asserts completeness at build time. A hand with no mechanism is a routing
-- hole, and a hole found here is found once, at startup, rather than on the
-- day somebody first declares an operation that prefers the missing hand.
function Mechanism.dispatch(neuron_root)
    local mechanisms = {}

    for _, file in ipairs({ "035-cold.lua", "036-live.lua",
                            "037-resident.lua", "038-none.lua" }) do
        local mechanism = Load(neuron_root .. "/src/033-mechanisms/" .. file)
        mechanisms[mechanism.hand] = mechanism
    end

    local unrouted = {}
    for _, member in ipairs(Hands.members) do
        if not mechanisms[member] then table.insert(unrouted, member.name) end
    end

    if #unrouted > 0 then
        error(string.format(
            "Mechanism.dispatch: no mechanism for %s.\n"
         .. "  Every member of the Hands enum needs one, because an operation is\n"
         .. "  free to declare any of them as a preference and the dispatcher\n"
         .. "  indexes this table directly. A missing entry is not a nil check\n"
         .. "  somewhere later; it is a hand nobody can reach.",
            table.concat(unrouted, ", ")), 2)
    end

    return mechanisms
end
-- }}}

return Mechanism
