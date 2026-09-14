--------------------------------------------------------------------------------
-- 035-cold.lua
--
-- The cold hand as a mechanism: a database write through the deployment's own
-- MySQL socket.
--
-- A doorway onto 002-cold-hand.lua, which is unchanged. Everything about how a
-- statement is bound, how values are escaped, and how the socket is probed
-- lives there and has been exercised against twenty-five thousand real rows.
--------------------------------------------------------------------------------

local here = debug.getinfo(1, "S").source:match("^@(.*/)")
local Load = dofile(here .. "../024-load.lua")

local Mechanism = Load(here .. "034-mechanism.lua")
local Hands     = Mechanism.Hands
local Refusals  = Mechanism.Refusals

return Mechanism.define {
    hand = Hands.cold,

    -- {{{ probe
    probe = function(handle)
        local ColdHand = Load(handle.neuron_root .. "/src/002-cold-hand.lua")
        return ColdHand.probe(handle)
    end,
    -- }}}

    -- {{{ describes
    describes = function(step)
        return step.describes or ("cold write to " .. tostring(step.database))
    end,
    -- }}}

    -- {{{ perform
    -- One parameterised statement, one round trip, one affected-row count.
    --
    -- Zero affected rows is reported as zero and is NOT an error here. A write
    -- that changed nothing usually means the world was already the way it was
    -- being asked to be -- a character teleported to where they were already
    -- standing. Whether zero is wrong is the operation's judgment, made against
    -- what it expected, not the mechanism's.
    perform = function(handle, step)
        local ColdHand = Load(handle.neuron_root .. "/src/002-cold-hand.lua")

        local affected, why = ColdHand.write(handle, step.database,
                                             step.sql, step.binds)

        if not affected then
            return Mechanism.failed(Refusals.unavailable, string.format(
                "the cold hand could not run this step.\n"
             .. "  %s\n"
             .. "  Ran against: %s\n"
             .. "  The step: %s\n"
             .. "  To debug: is the database up? `scripts/status` probes it and\n"
             .. "  distinguishes a missing socket from a stale one left by a\n"
             .. "  crashed MySQL, which are different problems. If it is up,\n"
             .. "  the statement itself is malformed and the message above is\n"
             .. "  the server's own words about it.",
                tostring(why), tostring(step.database),
                step.describes or "(no description)"))
        end

        return Mechanism.done(affected, string.format("%d row%s",
            affected, affected == 1 and "" or "s"))
    end,
    -- }}}
}
