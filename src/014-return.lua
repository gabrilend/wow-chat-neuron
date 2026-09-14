--------------------------------------------------------------------------------
-- 014-return.lua
--
-- Put them back. Reads a receipt, builds the inverse steps from the values it
-- captured before overwriting, and applies them.
--
-- THIS IS A SECOND OPERATION, NOT A ROLLBACK. An apply that fails stops and
-- leaves a partial change; it does not unwind itself, because unwinding needs
-- the same guards and the same liveness as going forward, and a failed rollback
-- inside a failed apply is a worse place to be than a half-changed world with an
-- exact record of itself.
--
-- So reversal is deliberate. It plans, it can be dry-run, it is guarded like
-- anything else, and it writes a receipt of its own -- which means an undo can
-- itself be undone.
--
-- KEYED BY GUID, NEVER BY NAME. A receipt records both. A character can be
-- renamed, and a name freed by a rename can be taken by somebody else; restoring
-- "the character now called Aalaan" rather than "the character that was moved"
-- is how the wrong person ends up somewhere.
--
-- See issues/205-return.md for the blueprint.
--------------------------------------------------------------------------------

local Return = {}

-- {{{ sibling(neuron_root, filename)
local function sibling(neuron_root, filename)
    return dofile(neuron_root .. "/src/" .. filename)
end
-- }}}

-- {{{ Return.declaration
Return.declaration = {
    name    = "character.return",
    summary = "Put characters back where a receipt says they were.",
    hands   = { "cold" },
    kind    = "change",   -- reversible: apply captures the prior value first
    params  = {
        { name = "receipt", type = "receipt", required = true,
          describes = "The id of the receipt to reverse, as shown by 'neuron receipts'." },
    },
}
-- }}}

-- {{{ find_receipt(handle, id)
-- Look up a receipt by id across every dated log, not just today's.
--
-- Undoing something the next morning is the common case, and a lookup that only
-- searched today would fail at exactly the moment somebody most wants it.
--
-- The logs live in RAM and do not survive a reboot. A receipt that cannot be
-- found may therefore be gone rather than mistyped, and the message says so --
-- the two have very different implications for what to do next.
local function find_receipt(handle, id)
    local Receipts = sibling(handle.neuron_root, "006-receipts.lua")

    -- Walk the receipt directory. `ls` rather than a directory library, because
    -- LuaJIT ships no filesystem module and this project takes no dependencies.
    local listing = io.popen("ls -1 '" .. handle.receipts_dir:gsub("'", "'\\''")
        .. "' 2>/dev/null")
    if not listing then
        return nil, "cannot read the receipt directory at " .. handle.receipts_dir
    end

    local dates = {}
    for name in listing:lines() do
        local date = name:match("^(%d%d%d%d%-%d%d%-%d%d)%.log$")
        if date then table.insert(dates, date) end
    end
    listing:close()

    -- Newest first, since a receipt somebody wants to undo is usually recent.
    table.sort(dates, function(a, b) return a > b end)

    for _, date in ipairs(dates) do
        local found = Receipts.read(handle, { date = date })
        for _, receipt in ipairs(found) do
            if receipt.id == id then
                return receipt
            end
        end
    end

    return nil, "no receipt with id '" .. id .. "'.\n"
             .. "  Receipts live in RAM and do not survive a reboot, so it may be\n"
             .. "  gone rather than mistyped. 'neuron receipts' lists what remains."
end
-- }}}

-- {{{ RESTORABLE_OUTCOMES
-- Which step outcomes represent a change that can be undone.
--
-- `done` and `rerouted` changed something. `failed`, `refused`, and `skipped`
-- did not -- and reversing one of those would move a character who was never
-- moved, which is the specific bug this table exists to prevent.
local RESTORABLE_OUTCOMES = {
    done     = true,
    rerouted = true,
}
-- }}}

-- {{{ Return.plan(handle, args)
-- Build the inverse of a receipt.
function Return.plan(handle, args)
    local WorldRead = sibling(handle.neuron_root, "005-world-read.lua")

    local receipt, why = find_receipt(handle, args.receipt)
    if not receipt then
        return nil, why
    end

    -- A receipt from a DIFFERENT profile is a refusal, not a warning. Restoring
    -- characters using coordinates recorded in another world is a catastrophe
    -- that would look, from the outside, like the tool working.
    if receipt.profile ~= handle.profile then
        return nil, string.format(
            "that receipt was written against profile '%s' and this deployment is "
         .. "running '%s'.\n  Restoring characters to coordinates from a different "
         .. "world is not something to warn about.", receipt.profile, handle.profile)
    end

    local steps, guids = {}, {}

    for _, step in ipairs(receipt.steps or {}) do
        if RESTORABLE_OUTCOMES[step.outcome]
           and step.restores
           and step.subject
           and step.subject.guid then

            local restores = step.restores
            table.insert(guids, step.subject.guid)

            table.insert(steps, {
                hand      = "cold",
                -- Described in terms of where they are GOING, since that is what
                -- a person approving this needs to picture.
                describes = string.format("%s  back to map %s  %.0f,%.0f",
                    step.subject.name,
                    tostring(restores.map),
                    tonumber(restores.position_x) or 0,
                    tonumber(restores.position_y) or 0),
                sql       = "UPDATE characters SET map = ?, position_x = ?, "
                         .. "position_y = ?, position_z = ?, orientation = ? "
                         .. "WHERE guid = ?",
                binds     = { tonumber(restores.map),
                              tonumber(restores.position_x),
                              tonumber(restores.position_y),
                              tonumber(restores.position_z),
                              tonumber(restores.orientation) or 0,
                              step.subject.guid },
                subject   = { guid = step.subject.guid, name = step.subject.name },
                restores_from = {
                    table  = "characters",
                    key    = { guid = step.subject.guid },
                    fields = { "map", "position_x", "position_y",
                               "position_z", "orientation" },
                },
                -- What THIS step writes, so the undo's own receipt supports
                -- an undo of the undo.
                wrote = { map = tonumber(restores.map),
                          position_x = tonumber(restores.position_x),
                          position_y = tonumber(restores.position_y),
                          position_z = tonumber(restores.position_z),
                          orientation = tonumber(restores.orientation) or 0 },
                -- Where the original step LEFT them. Drift is measured against
                -- this, not against where it took them from.
                left_at = step.wrote,
            })
        end
    end

    if #steps == 0 then
        return nil, "that receipt has nothing to undo -- none of its steps both "
                 .. "succeeded and captured a prior value"
    end

    -- Drift check. A character may have moved again since, by another operation
    -- or by being played. Restoring them to a stale position is well-defined and
    -- possibly not what anybody wants, so it is REPORTED rather than refused --
    -- the person deciding has context this code does not.
    local current = WorldRead.characters_by_guid(handle, guids)
    local by_guid = {}
    for _, character in ipairs(current or {}) do
        by_guid[character.guid] = character
    end

    local drifted, vanished = {}, {}
    for _, step in ipairs(steps) do
        local now = by_guid[step.subject.guid]
        if not now then
            table.insert(vanished, step.subject.name)
        elseif step.left_at then
            -- Compare against where the original operation LEFT them. Differing
            -- from where it TOOK them from is not drift -- it is the operation
            -- having worked.
            --
            -- Coordinates are compared with a tolerance rather than for
            -- equality: the columns are 4-byte floats and the values passed
            -- through Lua doubles, so an untouched character reads back a
            -- fraction of a yard off and an exact comparison would report every
            -- single one as drifted.
            local moved = now.map ~= step.left_at.map
                or math.abs(now.x - (step.left_at.position_x or 0)) > 0.5
                or math.abs(now.y - (step.left_at.position_y or 0)) > 0.5
            if moved then
                table.insert(drifted, string.format(
                    "%s has moved since -- now on map %d at %.0f,%.0f",
                    now.name, now.map, now.x, now.y))
            end
        end
    end

    return {
        operation = Return.declaration.name,
        source    = receipt,
        steps     = steps,
        drifted   = drifted,
        vanished  = vanished,
    }
end
-- }}}

-- {{{ Return.describe_plan(plan)
function Return.describe_plan(plan)
    local lines = {}

    table.insert(lines, string.format("put %d character%s back, from receipt %s (%s)",
        #plan.steps, #plan.steps == 1 and "" or "s",
        plan.source.id, plan.source.operation))
    table.insert(lines, "")

    for _, step in ipairs(plan.steps) do
        table.insert(lines, string.format("  %-7s %s", step.hand, step.describes))
    end

    if #plan.drifted > 0 then
        table.insert(lines, "")
        table.insert(lines, "NOTE: some have moved since that receipt was written --")
        for _, note in ipairs(plan.drifted) do
            table.insert(lines, "      " .. note)
        end
        table.insert(lines, "      Putting them back is still well-defined; it may "
                         .. "not be what you want.")
    end

    if #plan.vanished > 0 then
        table.insert(lines, "")
        table.insert(lines, "GONE: these no longer exist and will be skipped -- "
            .. table.concat(plan.vanished, ", "))
    end

    return table.concat(lines, "\n")
end
-- }}}

-- {{{ Return.apply(handle, plan, state)
-- Reuse teleport's apply. The inverse is an ordinary plan and goes through
-- ordinary machinery -- guarding, prior-value capture, receipt writing -- rather
-- than a parallel path that would have to be kept in step with it.
function Return.apply(handle, plan, state)
    local Teleport = sibling(handle.neuron_root, "013-teleport.lua")
    return Teleport.apply(handle, {
        operation  = plan.operation,
        place      = { name = "their previous positions" },
        resolution = { describes = "from receipt " .. plan.source.id,
                       missing = {}, truncated = false },
        steps      = plan.steps,
    }, state)
end
-- }}}

return Return
