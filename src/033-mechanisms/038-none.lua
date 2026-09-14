--------------------------------------------------------------------------------
-- 038-none.lua
--
-- The hand that does not reach anywhere.
--
-- It exists so that neuron.catalogue and neuron.explain are ordinary
-- operations, routed the ordinary way, rather than special cases the dispatcher
-- checks for before it does its real work. A mechanism that does nothing is
-- cheaper than a branch that means nothing, and it keeps the routing table
-- complete -- which is what lets the table assert its own completeness at load.
--------------------------------------------------------------------------------

local here = debug.getinfo(1, "S").source:match("^@(.*/)")
local Load = dofile(here .. "../024-load.lua")

local Mechanism = Load(here .. "034-mechanism.lua")
local Hands     = Mechanism.Hands

return Mechanism.define {
    hand = Hands.none,

    -- {{{ probe
    -- Always up. There is nothing to be down.
    probe = function() return true, "up", "no world contact needed" end,
    -- }}}

    -- {{{ describes
    describes = function(step)
        return step.describes or "answer about neuron itself"
    end,
    -- }}}

    -- {{{ perform
    -- Nothing changed, and nothing was supposed to. An operation on this hand
    -- has already produced its answer during plan; there is no world half.
    perform = function(_, step)
        return Mechanism.done(0, step.describes or "answered")
    end,
    -- }}}
}
