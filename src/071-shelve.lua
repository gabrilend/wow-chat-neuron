--------------------------------------------------------------------------------
-- 071-shelve.lua
--
-- `character.retire` and `character.restore` -- the deleted queue.
--
-- WHAT CHANGED AND WHY. Retiring used to be the one operation in this project
-- that could not be undone: thirty-nine DELETE statements transcribed from the
-- core's own Player::DeleteFromDB, a backup taken first, and a receipt that
-- could say what was destroyed but not rebuild it. It was `final`, the kind
-- that exists to mark exactly that.
--
-- A model should not be able to reach an operation of that kind at all. Not
-- because a model is careless -- a person with a roster query is just as
-- capable of turning "remove the companions" into "remove my characters" -- but
-- because the gap between those two sentences is one query, and something that
-- cannot be undone should require the sort of deliberation a conversation does
-- not have.
--
-- THE GAME ALREADY SOLVED THIS. AzerothCore has a deleted queue. A character
-- removed in the client is not erased; its name and account are moved into
-- deleteInfos_Name and deleteInfos_Account, deleteDate is stamped, and name and
-- account are blanked so the character vanishes from every list and the name is
-- free again. It stays that way for CharDelete.KeepDays -- thirty days on this
-- deployment -- and the worldserver purges it at startup after that.
--
-- So retiring writes the same two rows the game writes, and restoring writes
-- the two the game writes back. Both statements below are copied from
-- CharacterDatabase.cpp (CHAR_UPD_DELETE_INFO and CHAR_UDP_RESTORE_DELETE_INFO)
-- rather than invented, for the same reason the deletion list was: the game's
-- idea of what these columns mean is the only one that matters, and a
-- hand-written version differs in exactly the way nobody notices until a
-- character comes back wrong.
--
-- The permanent version still exists, in 015-retire.lua, now called
-- `character.purge`. It is not in any vocabulary. It is reachable from the
-- command line, where somebody is typing a flag rather than a sentence, and it
-- is what cleans up the nine hundred characters whose accounts were deleted
-- years ago.
--------------------------------------------------------------------------------

local Shelve = {}

-- {{{ sibling(neuron_root, filename)
local function sibling(neuron_root, filename)
    return dofile(neuron_root .. "/src/" .. filename)
end
-- }}}

-- {{{ keep_days(handle)
-- How long the queue holds them, read from the deployment's own config.
--
-- Read rather than assumed. Telling somebody a character is recoverable for
-- thirty days when the config says seven is worse than saying nothing, and the
-- number is one line away.
local function keep_days(handle)
    local path = string.format("%s/installed-files-%s/etc/worldserver.conf",
        handle.root, handle.profile)

    local file = io.open(path, "r")
    if not file then return nil end

    for line in file:lines() do
        local value = line:match("^%s*CharDelete%.KeepDays%s*=%s*(%d+)")
        if value then file:close() return tonumber(value) end
    end

    file:close()
    return nil
end
-- }}}

-- {{{ Shelve.Retire
Shelve.Retire = {}

Shelve.Retire.declaration = {
    name    = "character.retire",
    summary = "Move characters to the game's deleted queue. They vanish from "
           .. "every list and their names are freed, and they can be brought "
           .. "back with character.restore until the server purges the queue.",
    hands   = { "cold" },
    -- `change`, not `final`. The receipt holds the name and account, which is
    -- everything the restore needs -- and the restore does not even need the
    -- receipt, because the game keeps the same two values in the row.
    kind    = "change",
    params  = {
        { name = "roster", type = "roster", required = true,
          describes = "Who to move to the queue. A name, a list of names, or a "
                   .. "query." },
    },
}

-- {{{ Shelve.Retire.plan(handle, args)
function Shelve.Retire.plan(handle, args)
    local Rosters = sibling(handle.neuron_root, "012-rosters.lua")

    local resolution, why = Rosters.resolve(handle, args.roster,
        { limit = args.limit or 100000 })
    if not resolution then return nil, why end

    if #resolution.characters == 0 then
        return nil, "that roster resolves to nobody, so there is nothing to "
                 .. "move to the queue."
    end

    local steps = {}
    for _, character in ipairs(resolution.characters) do
        table.insert(steps, {
            hand      = "cold",
            guid      = character.guid,
            name      = character.name,
            account   = character.account,
            describes = string.format("move %s to the deleted queue",
                character.name),
        })
    end

    return {
        operation  = Shelve.Retire.declaration.name,
        resolution = resolution,
        steps      = steps,
        days       = keep_days(handle),
    }
end
-- }}}

-- {{{ Shelve.Retire.describe_plan(plan)
function Shelve.Retire.describe_plan(plan)
    local lines = {}

    table.insert(lines, string.format("move %d character%s to the deleted queue",
        #plan.steps, #plan.steps == 1 and "" or "s"))
    table.insert(lines, "")

    for index = 1, math.min(#plan.steps, 12) do
        table.insert(lines, "  " .. plan.steps[index].name)
    end

    if #plan.steps > 12 then
        table.insert(lines, string.format("  ...and %d more", #plan.steps - 12))
    end

    table.insert(lines, "")

    -- The number, or the absence of it, said out loud. "Recoverable for a
    -- while" is not a thing anybody can plan around.
    if plan.days then
        table.insert(lines, string.format(
            "They disappear from every list and their names become free. "
         .. "character.restore brings them back for the next %d days, after "
         .. "which the worldserver purges the queue and they are gone.",
            plan.days))
    else
        table.insert(lines,
            "They disappear from every list and their names become free. "
         .. "character.restore brings them back until the worldserver purges "
         .. "the queue -- CharDelete.KeepDays could not be read from this "
         .. "profile's config, so how long that is is not known from here.")
    end

    return table.concat(lines, "\n")
end
-- }}}

-- {{{ Shelve.Retire.apply(handle, plan, state)
function Shelve.Retire.apply(handle, plan, state)
    local ColdHand = sibling(handle.neuron_root, "002-cold-hand.lua")
    local Receipts = sibling(handle.neuron_root, "006-receipts.lua")

    local receipt = Receipts.begin(handle, plan.operation, {
        roster     = plan.resolution.describes,
        characters = #plan.steps,
    })

    for _, step in ipairs(plan.steps) do
        -- The core's own statement, verbatim. It reads name and account out of
        -- the row it is writing, so the values move rather than being copied by
        -- us -- which means they are right even if what we read a moment ago
        -- was already stale.
        local ok, why = ColdHand.write(handle, handle.db_characters,
            "UPDATE characters SET deleteInfos_Name = name, "
         .. "deleteInfos_Account = account, deleteDate = UNIX_TIMESTAMP(), "
         .. "name = '', account = 0 WHERE guid = ? AND deleteDate IS NULL",
            { step.guid })

        if ok then
            -- What it takes to put this one back, in the receipt. The row keeps
            -- the same two values, so this is a second copy -- and a second
            -- copy is what makes the receipt readable as a record of what
            -- happened rather than a pointer into a database that has moved on.
            Receipts.record(receipt, step, "done",
                { name = step.name, account = step.account },
                "moved to the queue")
        else
            Receipts.record(receipt, step, "failed", nil, why)
        end
    end

    Receipts.finish(receipt)
    Receipts.append(handle, receipt)
    return receipt
end
-- }}}
-- }}}

-- {{{ Shelve.Restore
Shelve.Restore = {}

Shelve.Restore.declaration = {
    name    = "character.restore",
    summary = "Bring characters back out of the deleted queue, by the name they "
           .. "had when they went in.",
    hands   = { "cold" },
    kind    = "change",
    params  = {
        { name = "names", type = "string", required = true,
          describes = "The name of the character to bring back, or several "
                   .. "separated by commas." },
    },
}

-- {{{ Shelve.Restore.plan(handle, args)
function Shelve.Restore.plan(handle, args)
    local ColdHand = sibling(handle.neuron_root, "002-cold-hand.lua")

    local wanted = {}
    for piece in tostring(args.names or ""):gmatch("[^,]+") do
        local name = piece:gsub("^%s+", ""):gsub("%s+$", "")
        if name ~= "" then table.insert(wanted, name) end
    end

    if #wanted == 0 then
        return nil, "which characters? Name one, or several separated by commas."
    end

    -- Matched on deleteInfos_Name, because that is where the name went. The
    -- `name` column is empty for anything in the queue -- that is what frees
    -- the name for somebody else -- so looking there finds nothing and the
    -- answer would be "no such character" about a character that is right
    -- there.
    local steps, missing = {}, {}

    for _, name in ipairs(wanted) do
        local rows, why = ColdHand.read(handle, handle.db_characters,
            "SELECT guid, deleteInfos_Name, deleteInfos_Account, deleteDate "
         .. "FROM characters WHERE deleteDate IS NOT NULL "
         .. "AND deleteInfos_Name = ?", { name })

        if not rows then return nil, why end

        if #rows == 0 then
            table.insert(missing, name)
        else
            local row = rows[1]
            table.insert(steps, {
                hand      = "cold",
                guid      = tonumber(row.guid),
                name      = row.deleteInfos_Name,
                account   = tonumber(row.deleteInfos_Account),
                describes = string.format("bring %s back out of the queue",
                    row.deleteInfos_Name),
            })
        end
    end

    if #steps == 0 then
        return nil, string.format(
            "nothing in the deleted queue is called %s.\n"
         .. "  The queue holds characters that were retired and not yet purged. "
         .. "A character that was never retired is not in it, and one the "
         .. "worldserver has already purged is gone.",
            table.concat(missing, " or "))
    end

    return {
        operation = Shelve.Restore.declaration.name,
        steps     = steps,
        missing   = missing,
    }
end
-- }}}

-- {{{ Shelve.Restore.describe_plan(plan)
function Shelve.Restore.describe_plan(plan)
    local lines = {}

    table.insert(lines, string.format("bring %d character%s back out of the "
        .. "deleted queue", #plan.steps, #plan.steps == 1 and "" or "s"))
    table.insert(lines, "")

    for _, step in ipairs(plan.steps) do
        table.insert(lines, "  " .. step.name)
    end

    if #plan.missing > 0 then
        table.insert(lines, "")
        table.insert(lines, "Not in the queue, and not touched: "
            .. table.concat(plan.missing, ", "))
    end

    return table.concat(lines, "\n")
end
-- }}}

-- {{{ Shelve.Restore.apply(handle, plan, state)
function Shelve.Restore.apply(handle, plan, state)
    local ColdHand = sibling(handle.neuron_root, "002-cold-hand.lua")
    local Receipts = sibling(handle.neuron_root, "006-receipts.lua")

    local receipt = Receipts.begin(handle, plan.operation, {
        characters = #plan.steps,
    })

    for _, step in ipairs(plan.steps) do
        -- The core's own restore, verbatim. The `deleteDate IS NOT NULL` guard
        -- is part of it and is doing real work: without it, this would happily
        -- rename a live character to whatever was in the queue.
        local ok, why = ColdHand.write(handle, handle.db_characters,
            "UPDATE characters SET name = ?, account = ?, deleteDate = NULL, "
         .. "deleteInfos_Name = NULL, deleteInfos_Account = NULL "
         .. "WHERE deleteDate IS NOT NULL AND guid = ?",
            { step.name, step.account, step.guid })

        Receipts.record(receipt, step, ok and "done" or "failed",
            ok and { deleted = true } or nil,
            ok and "back out of the queue" or why)
    end

    Receipts.finish(receipt)
    Receipts.append(handle, receipt)
    return receipt
end
-- }}}
-- }}}

return Shelve
