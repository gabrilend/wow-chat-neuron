--------------------------------------------------------------------------------
-- 040-relevance.lua
--
-- How much of a creature's attention each of its memories gets right now.
--
-- Three stores compete for one context budget. The chatlog holds verbatim
-- speech and COOLS -- any line appended, heard or said, snaps it back to full
-- and it decays from there. The scratchspace holds atoms and does not cool at
-- all; it forgets by falling off the end of a fixed ring. The playersheet holds
-- what was deliberately kept and never cools, because a thing somebody chose to
-- remember does not become less true by being old.
--
-- So exactly one of the three has a clock, and this file is that clock plus the
-- arithmetic that turns three relevances into three allocations of a fixed
-- budget.
--
-- Pure. No world, no deployment, no clock of its own -- `now` is always passed
-- in, so a test can move time without waiting for it.
--------------------------------------------------------------------------------

local Relevance = {}

-- {{{ CURVE
-- The chatlog's decay, and the only tuned numbers in this file.
--
-- HALF_LIFE is stated rather than a slope because half-life is the parameter a
-- person can reason about: "half gone in eight seconds" is a sentence about
-- behaviour, and "slope of -0.033" is not.
--
-- Eight seconds puts relevance near 7% at thirty, which is the "~30 seconds to
-- fade" this was specified as -- cool enough that the ring and the sheet have
-- the room, without a corner where the conversation abruptly stops existing. A
-- creature drifts out of a conversation; it does not fall out of one.
--
-- RESTING is where the curve settles. Zero means a conversation eventually
-- means nothing at all, and what survives is the atom `note` distilled out of
-- it. A non-zero resting value would be a creature that never fully leaves a
-- conversation -- a different creature, possibly a better one, and the knob is
-- here to find out. Changes belong in docs/balance-updates.md.
local CURVE = {
    half_life = 8.0,   -- seconds for relevance to fall halfway to resting
    resting   = 0.0,   -- where it settles
    full      = 1.0,   -- where any new line puts it, instantly
}

Relevance.CURVE = CURVE
-- }}}

-- {{{ Relevance.chatlog(last_change, now, curve)
-- The chatlog's share, from when it last changed.
--
-- `last_change` is when a line was last appended IN EITHER DIRECTION. That both
-- directions reset it is what makes this a conversation rather than a
-- broadcast: a creature part-way through saying two things does not cool
-- between them and wander off mid-thought.
--
-- Nothing is deleted when relevance falls. The words are all still there and
-- only dimmed, which is why speaking after twenty-eight seconds of silence puts
-- the creature fully back into a conversation it still has every word of,
-- rather than into one it has to have re-established.
function Relevance.chatlog(last_change, now, curve)
    curve = curve or CURVE

    local elapsed = now - last_change

    -- Time running backwards means a clock was adjusted or two clocks are being
    -- compared. Treating it as zero would silently report a stale conversation
    -- as fully hot, which is the wrong direction to be wrong in -- a creature
    -- that believes it is mid-conversation with somebody who left is worse than
    -- one that has cooled early.
    if elapsed < 0 then
        return nil, string.format(
            "the chatlog last changed %.3f seconds in the future.\n"
         .. "  last change: %.3f   now: %.3f\n"
         .. "  Time does not run backwards, so these two readings came from\n"
         .. "  different clocks. To debug: is `now` the worldserver's clock and\n"
         .. "  `last_change` neuron's? They are different machines' ideas of the\n"
         .. "  time even when they are the same machine, because one is a tick\n"
         .. "  counter and one is a wall clock.", -elapsed, last_change, now)
    end

    -- Exponential toward resting. At elapsed == 0 this is `full` exactly; at
    -- one half-life it is halfway between resting and full; it approaches
    -- resting and never overshoots it.
    local remaining = 0.5 ^ (elapsed / curve.half_life)

    return curve.resting + (curve.full - curve.resting) * remaining
end
-- }}}

-- {{{ Relevance.weigh(state, now, curve)
-- All three relevances at once.
--
-- The ring and the sheet are constants and that is the point of them. A store
-- that cooled would be a store whose contents become less true with age, and
-- neither of those does: an atom on the ring is either still there or has
-- fallen off, and an atom on the sheet was chosen and stays chosen.
--
-- Their weights say how much room each gets when nothing is being said, and
-- they are relative to the chatlog's `full`, not to each other in isolation.
function Relevance.weigh(state, now, curve)
    curve = curve or CURVE

    local chatlog, why = Relevance.chatlog(state.chatlog_changed, now, curve)
    if not chatlog then return nil, why end

    return {
        chatlog = chatlog,
        -- The ring is what the creature is standing in. It is always somewhat
        -- present, and a conversation at full relevance crowds it rather than
        -- silencing it -- somebody talking to you does not stop you seeing the
        -- room.
        ring    = state.ring_weight  or 0.60,
        -- The sheet is who the creature is. Least room moment to moment, and
        -- never none, because a creature that stops being able to reach what it
        -- deliberately remembered is a creature with no character between
        -- sentences.
        sheet   = state.sheet_weight or 0.35,
    }
end
-- }}}

-- {{{ Relevance.budget(weights, total)
-- Turn relevances into whole allocations of a fixed budget, summing EXACTLY to
-- the total.
--
-- The exactness is the reason this is a function rather than three
-- multiplications at the call site. Rounding three proportions independently
-- does not sum to the total -- three shares of 100 that are each 33.33 round to
-- 99, and three that are each 33.34 round to 102. One is a wasted line of
-- context and the other is a truncated prompt, and a prompt truncated at the
-- end loses whatever was most recent, which is exactly the part that mattered.
--
-- Largest remainder: floor everything, then hand the leftover units out one at a
-- time to whoever was cheated most by the flooring. Deterministic, and it puts
-- the spare unit where it does the most good rather than wherever the iteration
-- order happened to land.
function Relevance.budget(weights, total)
    if total < 0 then
        error("Relevance.budget: a negative budget is not a small budget. "
           .. "Got: " .. tostring(total), 2)
    end

    local names, sum = {}, 0

    for name, weight in pairs(weights) do
        if weight < 0 then
            error(string.format(
                "Relevance.budget: '%s' has a negative relevance (%s).\n"
             .. "  Relevance is a share of attention. A negative share would\n"
             .. "  have to take room away from another store, which is not a\n"
             .. "  thing this can express.", name, tostring(weight)), 2)
        end
        table.insert(names, name)
        sum = sum + weight
    end

    table.sort(names)   -- deterministic, so a tie breaks the same way twice

    -- Every store silent. Not an error -- a creature with nothing in any store
    -- is a creature that has just been made -- but there is nothing to divide.
    if sum == 0 then
        local empty = {}
        for _, name in ipairs(names) do empty[name] = 0 end
        return empty
    end

    local allocation, handed_out, remainders = {}, 0, {}

    for _, name in ipairs(names) do
        local exact  = weights[name] / sum * total
        local floored = math.floor(exact)

        allocation[name] = floored
        handed_out       = handed_out + floored

        table.insert(remainders, { name = name, owed = exact - floored })
    end

    -- Most-cheated first; name as the tiebreak so the result is reproducible.
    table.sort(remainders, function(left, right)
        if left.owed == right.owed then return left.name < right.name end
        return left.owed > right.owed
    end)

    local leftover = total - handed_out

    for index = 1, leftover do
        local receiver = remainders[((index - 1) % #remainders) + 1]
        allocation[receiver.name] = allocation[receiver.name] + 1
    end

    return allocation
end
-- }}}

-- {{{ Relevance.describe(weights, allocation)
-- One line per store, for a person watching a creature think.
--
-- This is the only window onto why a creature answered the way it did. A
-- creature that ignored the cherries because it was mid-conversation looks
-- identical, from outside, to one that never saw them.
function Relevance.describe(weights, allocation)
    local names = {}
    for name in pairs(weights) do table.insert(names, name) end
    table.sort(names)

    local lines = {}
    for _, name in ipairs(names) do
        table.insert(lines, string.format("  %-9s %5.1f%%   %d",
            name, weights[name] * 100, allocation and allocation[name] or 0))
    end
    return table.concat(lines, "\n")
end
-- }}}

return Relevance
