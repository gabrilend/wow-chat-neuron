--------------------------------------------------------------------------------
-- 004-liveness.lua
--
-- Combines the two hands' probes into one answer about what may run right now,
-- and holds the guard that prevents this project's most damaging mistake.
--
-- THE MISTAKE:
--
--   A running worldserver holds every logged-in character's state IN MEMORY. It
--   writes that state to the database on a save timer and at logout. A cold-hand
--   UPDATE against a character who is logged in succeeds, changes the row,
--   reports success -- and is then overwritten by the server's next save of that
--   player. Nothing errors anywhere. The tool appears broken, the database
--   appears correct, and somebody spends an afternoon on it.
--
-- Preventing that is mechanical, not advisory, and it lives here.
--
-- See issues/104-liveness-and-hand-availability.md for the blueprint.
--------------------------------------------------------------------------------


local Liveness = {}

-- {{{ module loading
-- Sibling modules are loaded by absolute path off the deployment handle's
-- neuron_root rather than through package.path, because this project is run
-- from arbitrary working directories and a relative require would resolve
-- differently depending on where the caller stood.
local function sibling(neuron_root, filename)
    return dofile(neuron_root .. "/src/" .. filename)
end
-- }}}

-- {{{ Liveness.probe(handle)
-- Ask both hands whether they are up. Returns one table.
--
-- Both probes always run, even when the first fails. Knowing that the database
-- is down AND the world is down is more useful than stopping at the first
-- failure, because it distinguishes "nothing is started" from "one thing
-- crashed", and those are different mornings.
function Liveness.probe(handle)
    local cold = sibling(handle.neuron_root, "002-cold-hand.lua")
    local live = sibling(handle.neuron_root, "003-live-hand.lua")

    local db_up,    db_reason,    db_detail    = cold.probe(handle)
    local world_up, world_reason, world_detail = live.probe(handle)

    return {
        db_up        = db_up,
        db_reason    = db_reason,
        db_detail    = db_detail,
        world_up     = world_up,
        world_reason = world_reason,
        world_detail = world_detail,
    }
end
-- }}}

-- {{{ Liveness.fault(state)
-- Detect the combination that should be impossible.
--
-- A worldserver cannot run without its database. If the world answers while the
-- database does not, then either a probe is lying or neuron is pointed at a
-- different deployment than it believes. Both are worse than a service being
-- down, and both must stop the run rather than being warned about -- proceeding
-- from here would apply changes to a world other than the one being reported on.
function Liveness.fault(state)
    if state.world_up and not state.db_up then
        return "FAULT: the worldserver answered but its database did not.\n"
            .. "  A worldserver cannot run without its database, so one of these\n"
            .. "  is true and all of them are worse than a service being down:\n"
            .. "    - neuron is pointed at a different deployment than it thinks\n"
            .. "    - the configured MySQL socket belongs to a different instance\n"
            .. "    - the SOAP endpoint belongs to a different worldserver\n"
            .. "  database said: " .. tostring(state.db_detail)
    end
    return nil
end
-- }}}

-- {{{ Liveness.choose_hand(state, preference)
-- Pick the first hand in an operation's preference list that is actually up.
--
-- Preference order is per-operation and deliberate. Teleport prefers "live",
-- because the change is instant and visible to everyone standing there.
-- Bulk-relevelling forty offline bots prefers "cold", because forty GM commands
-- is forty round trips into a game server's main thread and one UPDATE with an
-- IN clause is one statement.
--
-- Returns the hand name, or nil plus a message naming what is down and what the
-- operation would have needed.
function Liveness.choose_hand(state, preference)
    local available = {
        cold     = state.db_up,
        live     = state.world_up,
        resident = state.world_up,  -- resident scripts run inside the worldserver
    }

    for _, hand in ipairs(preference) do
        if available[hand] then
            return hand
        end
    end

    local wanted = table.concat(preference, " or ")
    local down = {}
    if not state.db_up then
        table.insert(down, "database is down (" .. tostring(state.db_reason) .. ")")
    end
    if not state.world_up then
        table.insert(down, "worldserver is down (" .. tostring(state.world_reason) .. ")")
    end

    return nil, "this operation needs the " .. wanted .. " hand, but "
             .. table.concat(down, " and ")
end
-- }}}

-- {{{ Liveness.guard_step(handle, state, step)
-- The guard. Decide what happens to one step, immediately before it runs.
--
-- Three verdicts, and each one means something different to the caller:
--
--   "proceed"  nothing is in the way; run the step as planned
--   "reroute"  this cold write would be silently overwritten; the operation
--              should use its live form for this subject instead
--   "refuse"   this cold write would be silently overwritten and there is no
--              live form; do not write and hope
--
-- Timing is the point. This runs at APPLY time, not plan time. A plan that a
-- person reviewed for ten minutes is a plan whose subjects had ten minutes to
-- log in, and the whole value of the check is that it reflects the world as it
-- is when the write is about to land.
function Liveness.guard_step(handle, state, step)
    -- A step that is not a cold write to a character cannot hit this failure
    -- mode at all: live commands go through the server's own memory, resident
    -- scripts already run inside it, and a cold write to a world-database row
    -- has no in-memory player copy to be clobbered by.
    if step.hand ~= "cold" then
        return "proceed"
    end
    if not step.subject or not step.subject.guid then
        return "proceed"
    end

    -- With the world down there is no in-memory copy to overwrite the row, so
    -- the cold hand is not merely allowed here -- it is the only thing that
    -- works, and it works completely.
    if not state.world_up then
        return "proceed"
    end

    local cold = sibling(handle.neuron_root, "002-cold-hand.lua")
    local rows, why = cold.read(handle, handle.db_characters,
        "SELECT online FROM characters WHERE guid = ?", { step.subject.guid })

    if not rows then
        return "refuse", "could not check whether "
            .. tostring(step.subject.name) .. " is online: " .. tostring(why)
    end

    if #rows == 0 then
        return "refuse", "character " .. tostring(step.subject.name)
            .. " (guid " .. tostring(step.subject.guid) .. ") does not exist"
    end

    local online = tonumber(rows[1].online) == 1

    if not online then
        return "proceed"
    end

    if step.live_form then
        return "reroute"
    end

    return "refuse", tostring(step.subject.name) .. " is logged in. A database "
        .. "write to a logged-in character is overwritten by the server's next "
        .. "save of that player, silently. Either log them out, or stop the "
        .. "worldserver, or use an operation that has a live form."
end
-- }}}

-- {{{ Liveness.describe(state)
-- The matrix, rendered for a person.
--
-- Every reason string is written to name the fix rather than the symptom,
-- because the reason someone is reading this at all is that something did not
-- work and they want to know what to do next.
local FIX_FOR_REASON = {
    socket_missing     = "start the deployment's MySQL",
    socket_unreadable  = "check permissions on the deployment's mysql/databases directory",
    socket_stale       = "a crashed MySQL left its socket file behind; start MySQL",
    auth_failed        = "fix DB_PASS in the deployment's secrets.conf",
    no_credentials     = "set NEURON_SOAP_PASSWORD in neuron's secrets.conf",
    connection_refused = "start the worldserver, or enable SOAP in its config",
    soap_unauthorized  = "fix the SOAP account name or password",
    unreachable        = "check the SOAP address in config/deployment.lua",
    up                 = nil,
}

function Liveness.describe(state)
    local lines = {}

    local function line(label, up, reason, detail)
        local mark = up and "up  " or "down"
        local text = string.format("%-12s %s  (%s)", label, mark, tostring(reason))
        local fix  = FIX_FOR_REASON[reason]
        if fix then
            text = text .. "\n             -> " .. fix
        end
        if detail and not up then
            text = text .. "\n             " .. tostring(detail):gsub("\n", "\n             ")
        end
        table.insert(lines, text)
    end

    line("database", state.db_up, state.db_reason, state.db_detail)
    line("worldserver", state.world_up, state.world_reason, state.world_detail)

    table.insert(lines, "")

    if state.db_up and state.world_up then
        table.insert(lines, "hands        cold and live are both available.")
        table.insert(lines, "             Cold writes to LOGGED-IN characters will be")
        table.insert(lines, "             refused or rerouted -- they would be silently")
        table.insert(lines, "             overwritten by the server's next save.")
    elseif state.db_up then
        table.insert(lines, "hands        cold only. Free rein on character rows,")
        table.insert(lines, "             because nothing holds them in memory.")
    elseif state.world_up then
        table.insert(lines, "hands        none usable -- see the fault above.")
    else
        table.insert(lines, "hands        none. Nothing can run.")
    end

    return table.concat(lines, "\n")
end
-- }}}

return Liveness
