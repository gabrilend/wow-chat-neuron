--------------------------------------------------------------------------------
-- 015-retire.lua
--
-- Remove characters, and every row that refers to them.
--
-- THE ONLY OPERATION IN THIS PROJECT THAT CANNOT BE UNDONE. Every other one
-- captures prior values so a receipt can reverse it. This one cannot: restoring
-- a character needs every row from all thirty-nine tables, and a receipt holding
-- that for twenty-five thousand characters is a database, not a record.
--
-- "COMPLETELY" IS DEFINED BY THE GAME, NOT BY US. The statement list below is
-- transcribed from AzerothCore's own Player::DeleteFromDB in its
-- CHAR_DELETE_REMOVE mode. Inventing a table list instead is precisely how the
-- live deployment came to hold nine hundred characters that belong to nobody:
-- their accounts were deleted and their rows were left.
--
-- Four of the statements are keyed on something OTHER than the character's own
-- guid, and they are the ones a hand-written version always forgets. They are
-- marked below.
--
-- See issues/404-retire-characters.md for the blueprint.
--------------------------------------------------------------------------------

local Retire = {}

-- {{{ sibling(neuron_root, filename)
local function sibling(neuron_root, filename)
    return dofile(neuron_root .. "/src/" .. filename)
end
-- }}}

-- {{{ Retire.declaration
Retire.declaration = {
    -- RENAMED, and out of every vocabulary.
    --
    -- `character.retire` now means the game's deleted queue -- reversible, and
    -- purged by the worldserver after CharDelete.KeepDays. See 071-shelve.lua.
    -- This is the permanent one, and nothing a model can say reaches it: it is
    -- a command-line operation, for the case it was written for, which is the
    -- nine hundred characters whose accounts were deleted years ago and whose
    -- rows were left behind.
    name    = "character.purge",
    summary = "Erase characters and every row that refers to them, permanently. "
           .. "Not the deleted queue -- this is the end of it. Cannot be undone.",
    hands   = { "cold" },
    -- Stated as data, not as a comment, so anything reading the registry -- the
    -- command line and the tool schema -- can gate on it. `final` rather than a
    -- false `reversible`, because this writes a receipt that RECORDS what was
    -- destroyed and cannot put it back, and a boolean had no way to say that.
    kind    = "final",
    params = {
        { name = "roster", type = "roster", required = true,
          describes = "Who to remove. A name, a list of names, or a query." },
        { name = "confirm", type = "boolean", required = false,
          describes = "Required when the roster contains a character on a real, "
                   .. "non-bot account." },
    },
}
-- }}}

-- {{{ DELETIONS
-- The thirty-nine statements, in the core's own order.
--
-- Each carries the table, the column the character is identified by, and a note
-- where the column is not the obvious one. `?` stands for the guid set; the
-- builder substitutes a subquery against the temporary table, so one statement
-- covers the whole roster instead of one statement per character.
local DELETIONS = {
    -- Mail first, because mail items reference mail rows.
    { table = "mail_items",                        key = "receiver" },
    { table = "mail",                              key = "receiver",
      note  = "mail ADDRESSED TO them, not sent by them" },

    { table = "characters",                        key = "guid" },
    { table = "character_account_data",            key = "guid" },
    { table = "character_declinedname",            key = "guid" },
    { table = "character_action",                  key = "guid" },
    { table = "character_aura",                    key = "guid" },
    { table = "character_gifts",                   key = "guid" },
    { table = "character_homebind",                key = "guid" },
    { table = "character_instance",                key = "guid" },
    { table = "character_inventory",               key = "guid" },
    { table = "character_queststatus",             key = "guid" },
    { table = "character_queststatus_rewarded",    key = "guid" },
    { table = "character_reputation",              key = "guid" },
    { table = "character_spell",                   key = "guid" },
    { table = "character_spell_cooldown",          key = "guid" },

    { table = "gm_ticket",                         key = "playerGuid",
      note  = "open tickets -- NOT keyed on guid" },
    { table = "item_instance",                     key = "owner_guid",
      note  = "the item rows themselves, not just the inventory slots" },

    { table = "character_social",                  key = "guid" },
    { table = "character_social",                  key = "friend",
      note  = "removes them from OTHER PEOPLE'S friend lists -- the statement "
           .. "everyone forgets, and the one whose row count reveals a roster "
           .. "that caught somebody's friend" },

    { table = "character_pet",                     key = "owner" },
    { table = "character_pet_declinedname",        key = "owner" },
    { table = "character_achievement",             key = "guid" },
    { table = "character_achievement_progress",    key = "guid" },
    { table = "character_equipmentsets",           key = "guid" },
    { table = "guild_bank_eventlog",               key = "PlayerGuid" },
    { table = "character_entry_point",             key = "guid" },
    { table = "character_glyphs",                  key = "guid" },
    { table = "character_queststatus_daily",       key = "guid" },
    { table = "character_queststatus_weekly",      key = "guid" },
    { table = "character_queststatus_monthly",     key = "guid" },
    { table = "character_queststatus_seasonal",    key = "guid" },
    { table = "character_talent",                  key = "guid" },
    { table = "character_skills",                  key = "guid" },
    { table = "character_settings",                key = "guid" },
    { table = "character_achievement_offline_updates", key = "guid" },
    { table = "character_arena_stats",             key = "guid" },
    { table = "character_battleground_random",     key = "guid" },
    { table = "character_brew_of_the_month",       key = "guid" },
}

-- guild_eventlog is keyed on either of two columns, so it does not fit the
-- single-key shape above and is written out separately in the script builder.
local GUILD_EVENTLOG_COLUMNS = { "PlayerGuid1", "PlayerGuid2" }

Retire.DELETIONS = DELETIONS
-- }}}

-- {{{ TEMP_TABLE
-- The guid set lives in a temporary table for the life of ONE connection.
--
-- This is what turns 39 statements per character into 39 statements total. It is
-- also the thing that forces the whole job into a single connection, which is
-- the same thing the transaction needs, so the two requirements agree.
local TEMP_TABLE = "neuron_retire_guids"
-- }}}

-- {{{ build_script(guids)
-- Assemble the whole job as one SQL script.
--
-- Ordering inside the transaction does not matter for correctness -- it commits
-- or it does not -- but the core's order is kept anyway, so a reader comparing
-- this against Player::DeleteFromDB can follow along.
local function build_script(guids)
    local parts = {}

    local function line(text) table.insert(parts, text) end

    line("-- Written by neuron's character.retire. One connection, one transaction.")
    line("-- The temporary table dies with the connection whether this succeeds or not.")
    line("CREATE TEMPORARY TABLE " .. TEMP_TABLE .. " (guid INT UNSIGNED NOT NULL PRIMARY KEY) ENGINE=MEMORY;")

    -- Inserted in batches so no single statement is enormous. A thousand rows
    -- per INSERT keeps each statement comfortably under the packet limit while
    -- still being a handful of statements rather than twenty-five thousand.
    local batch = {}
    local function flush()
        if #batch > 0 then
            line("INSERT INTO " .. TEMP_TABLE .. " (guid) VALUES "
                .. table.concat(batch, ",") .. ";")
            batch = {}
        end
    end

    for _, guid in ipairs(guids) do
        table.insert(batch, "(" .. tonumber(guid) .. ")")
        if #batch >= 1000 then flush() end
    end
    flush()

    line("START TRANSACTION;")

    for _, deletion in ipairs(DELETIONS) do
        if deletion.note then
            line("-- " .. deletion.note)
        end
        line(string.format(
            "DELETE FROM `%s` WHERE `%s` IN (SELECT guid FROM %s);",
            deletion.table, deletion.key, TEMP_TABLE))
    end

    -- guild_eventlog names a character in either of two columns.
    for _, column in ipairs(GUILD_EVENTLOG_COLUMNS) do
        line(string.format(
            "DELETE FROM `guild_eventlog` WHERE `%s` IN (SELECT guid FROM %s);",
            column, TEMP_TABLE))
    end

    line("COMMIT;")

    return table.concat(parts, "\n") .. "\n"
end
-- }}}

-- {{{ build_count_script(guids, deletions)
-- Count what a set of statements would remove, in one connection.
--
-- Same shape as the deletion script and for the same reason: the guid list goes
-- into a temporary table once, and every count then refers to it by subquery
-- instead of carrying the list. Without this, describing a deletion of
-- twenty-five thousand characters means a statement longer than the command line
-- allows -- which is not a slow path, it is a broken one.
--
-- Each count is tagged with a literal prefix so the answers can be told apart
-- from the column headers the client prints around them.
local function build_count_script(guids, deletions)
    local parts = {}
    local function line(text) table.insert(parts, text) end

    line("CREATE TEMPORARY TABLE " .. TEMP_TABLE
        .. " (guid INT UNSIGNED NOT NULL PRIMARY KEY) ENGINE=MEMORY;")

    local batch = {}
    local function flush()
        if #batch > 0 then
            line("INSERT INTO " .. TEMP_TABLE .. " (guid) VALUES "
                .. table.concat(batch, ",") .. ";")
            batch = {}
        end
    end
    for _, guid in ipairs(guids) do
        table.insert(batch, "(" .. tonumber(guid) .. ")")
        if #batch >= 1000 then flush() end
    end
    flush()

    for _, deletion in ipairs(deletions) do
        line(string.format(
            "SELECT 'NEURONCOUNT', '%s', '%s', COUNT(*) FROM `%s` "
         .. "WHERE `%s` IN (SELECT guid FROM %s);",
            deletion.table, deletion.key, deletion.table, deletion.key, TEMP_TABLE))
    end

    return table.concat(parts, "\n") .. "\n"
end
-- }}}

-- {{{ Retire.plan(handle, args)
-- Work out what would be removed, per table.
--
-- The plan is PER TABLE, not per character. A plan listing twenty-five thousand
-- characters is not reviewable, and the per-table counts are the thing that
-- would actually reveal a mistake: an unexpected number against character_social
-- means the roster caught somebody's friend.
function Retire.plan(handle, args)
    local Rosters  = sibling(handle.neuron_root, "012-rosters.lua")
    local ColdHand = sibling(handle.neuron_root, "002-cold-hand.lua")

    local resolution, why = Rosters.resolve(handle, args.roster,
        { limit = args.limit or 100000, include_orphans = args.include_orphans })
    if not resolution then
        return nil, why
    end

    if #resolution.characters == 0 then
        return nil, "that roster resolves to nobody, so there is nothing to remove"
    end

    -- The guard that matters. The gap between "remove the companions" and
    -- "remove my characters" is one roster query, and this operation cannot be
    -- undone, so a real person's character requires saying so explicitly.
    local WorldRead = sibling(handle.neuron_root, "005-world-read.lua")
    local people = {}
    for _, character in ipairs(resolution.characters) do
        if WorldRead.kind_of(character) == "person" then
            table.insert(people, character.name)
        end
    end

    if #people > 0 and not args.confirm then
        return nil, string.format(
            "that roster contains %d character%s on a real account: %s.\n"
         .. "  This operation cannot be undone. Pass --confirm to include them.",
            #people, #people == 1 and "" or "s",
            table.concat(people, ", ", 1, math.min(#people, 10)))
    end

    local guids = {}
    for _, character in ipairs(resolution.characters) do
        table.insert(guids, character.guid)
    end

    -- Counting every table exactly would mean repeating the guid list once per
    -- table, which for twenty-five thousand guids is megabytes of SQL to
    -- describe a deletion -- slower than performing it.
    --
    -- So the roster size covers the thirty-five statements keyed on the
    -- character's own guid, where the count is knowable without asking, and
    -- exact counts are fetched only for the four keyed on something else. Those
    -- four are the only ones that can surprise, and surprise is the entire
    -- purpose of a plan.
    local surprising = {}
    for _, deletion in ipairs(DELETIONS) do
        if deletion.note then
            table.insert(surprising, deletion)
        end
    end

    -- Counted through a temporary table, for the same reason the deletion uses
    -- one: a guid list of twenty-five thousand entries pasted into a statement
    -- is hundreds of kilobytes, and a statement that long exceeds the command
    -- line the client is invoked on. The first version did exactly that, the
    -- read failed, and the counts were skipped in silence -- which is why the
    -- failure is now returned rather than swallowed.
    local exact = {}
    local count_script = build_count_script(guids, surprising)

    local output, count_why = ColdHand.script(handle, handle.db_characters,
        count_script, "retire-count")

    if not output then
        return nil, "could not count what would be removed: " .. tostring(count_why)
    end

    -- The script emits one "table<TAB>key<TAB>count" line per surprising
    -- statement, prefixed so the header rows the client also prints are ignored.
    local counted = {}
    for line in output:gmatch("[^\n]+") do
        local table_name, key, number = line:match("^NEURONCOUNT\t([^\t]+)\t([^\t]+)\t(%d+)$")
        if table_name then
            counted[table_name .. "." .. key] = tonumber(number)
        end
    end

    for _, deletion in ipairs(surprising) do
        local number = counted[deletion.table .. "." .. deletion.key]
        if number == nil then
            return nil, string.format(
                "the count for %s.%s came back missing. Refusing to describe a "
             .. "deletion whose reach is unknown.", deletion.table, deletion.key)
        end
        table.insert(exact, {
            table = deletion.table,
            key   = deletion.key,
            note  = deletion.note,
            count = number,
        })
    end

    return {
        operation  = Retire.declaration.name,
        resolution = resolution,
        guids      = guids,
        tables     = #DELETIONS + #GUILD_EVENTLOG_COLUMNS,
        exact      = exact,
        people     = people,
    }
end
-- }}}

-- {{{ Retire.describe_plan(plan)
function Retire.describe_plan(plan)
    local lines = {}

    table.insert(lines, string.format(
        "remove %d character%s, and every row referring to them, from %d tables",
        #plan.guids, #plan.guids == 1 and "" or "s", plan.tables))
    table.insert(lines, "")
    table.insert(lines, "  " .. plan.resolution.describes)

    if #plan.exact > 0 then
        table.insert(lines, "")
        table.insert(lines, "  statements NOT keyed on the character's own guid --")
        table.insert(lines, "  these are the ones that reach further than expected:")
        table.insert(lines, "")
        for _, entry in ipairs(plan.exact) do
            table.insert(lines, string.format("    %-24s %-12s %8d rows",
                entry.table, entry.key, entry.count))
            table.insert(lines, "      " .. entry.note)
        end
    end

    if #plan.people > 0 then
        table.insert(lines, "")
        table.insert(lines, "  INCLUDES REAL CHARACTERS: " .. table.concat(plan.people, ", "))
    end

    table.insert(lines, "")
    table.insert(lines, "  THIS CANNOT BE UNDONE. No prior values are captured, because")
    table.insert(lines, "  restoring a character needs every row from all these tables and")
    table.insert(lines, "  a receipt holding that is a database, not a record.")

    return table.concat(lines, "\n")
end
-- }}}

-- {{{ Retire.backup(handle)
-- Take a dump of the characters database before removing anything.
--
-- This is the actual safety net, and it is part of the operation rather than a
-- thing to remember. It goes to the RAM tier: that covers the risk that matters
-- -- something going wrong during the next few minutes -- and does NOT survive a
-- reboot, which the caller is told so a durable copy can be made deliberately.
function Retire.backup(handle)
    local dump = handle.root .. "/mysql/installed-files/bin/mysqldump"
    local path = "/dev/shm/wow-chat-neuron/" .. handle.db_characters
              .. "-before-retire-" .. os.date("%Y%m%dT%H%M%S") .. ".sql"

    local function quote(text) return "'" .. tostring(text):gsub("'", "'\\''") .. "'" end

    local errors = path .. ".stderr"

    local command = table.concat({
        "MYSQL_PWD=" .. quote(handle.mysql_password),
        quote(dump),
        "--no-defaults",
        -- Host and port, matching the cold hand. The socket field is gone:
        -- it was built from the project root, so it existed only on a
        -- deployment that keeps MySQL inside itself.
        "--host=" .. quote(handle.mysql_host),
        "--port=" .. tostring(handle.mysql_port),
        "--protocol=TCP",
        "--user="   .. quote(handle.mysql_user),
        -- NOT --single-transaction. On this client that issues FLUSH TABLES
        -- first, which needs the RELOAD privilege the deployment's database user
        -- does not hold, and the dump fails before writing a byte.
        --
        -- Skipping locks entirely is safe HERE and would not be in general: this
        -- operation already refuses to run while the worldserver is up, so
        -- nothing else is writing to these tables while the dump is taken. The
        -- guard that exists for a different reason -- not deleting rows out from
        -- under a live server -- is what makes an unlocked dump consistent.
        "--skip-lock-tables",
        -- The dump is for restoring rows into an existing schema, not for
        -- recreating storage layout, and reading tablespace metadata needs a
        -- privilege too.
        "--no-tablespaces",
        -- Without this, mysqldump writes `SET @@SESSION.SQL_LOG_BIN = 0` into
        -- the dump header, because binary logging is on. Setting that session
        -- variable needs SUPER or SYSTEM_VARIABLES_ADMIN, which the deployment's
        -- database user does not hold -- so the dump would refuse to load at its
        -- eighteenth line, for the SAME user that just wrote it.
        --
        -- A backup that cannot be restored by the credentials that made it is
        -- not a backup, and the failure appears only at restore time: exactly
        -- when somebody has already lost something and is relying on it. Found
        -- by actually restoring one rather than by trusting that the file
        -- existed and was the right size.
        "--set-gtid-purged=OFF",
        quote(handle.db_characters),
        -- Strip DEFINER clauses on the way out.
        --
        -- mysqldump writes the owning user into every trigger and view it
        -- dumps, and recreating one owned by a different user needs
        -- SET_ANY_DEFINER. This database has one trigger, owned by a user that
        -- is not the one the restore connects as, so the dump would refuse to
        -- load partway through -- after having already replaced some tables.
        -- Removing the clause makes the trigger belong to whoever restores it,
        -- which is the right answer and the only one available: mysqldump has
        -- no flag for this.
        -- mysqldump's stderr is captured HERE, before the pipe. A redirect at
        -- the end of a pipeline binds to the LAST command, so writing it there
        -- would collect sed's complaints and silently discard mysqldump's --
        -- which is how a failed backup reports "it failed" and nothing else.
        "2>", quote(errors),
        "|", "sed", "-E", quote([==[s|/\*!50017 DEFINER=[^*]*\*/||g]==]),
        ">", quote(path),
    }, " ")

    -- Run under bash with pipefail, so a mysqldump failure still fails the
    -- backup. Without it the exit status is sed's, sed succeeds on an empty
    -- stream, and a dump that never happened reports success -- which is the
    -- worst possible outcome for the one step standing between an irreversible
    -- deletion and losing everything.
    local ok = os.execute("bash -o pipefail -c " .. quote(command))
    if ok ~= true and ok ~= 0 then
        -- Read back what the tool actually said. An earlier version discarded
        -- stderr and reported only "mysqldump failed", which is a message that
        -- tells the reader nothing they did not already know.
        local detail = ""
        local handle_errors = io.open(errors, "r")
        if handle_errors then
            detail = handle_errors:read("*a") or ""
            handle_errors:close()
        end
        os.remove(path)
        os.remove(errors)
        return nil, "mysqldump failed, so nothing was removed:\n  "
                 .. detail:gsub("%s+$", ""):gsub("\n", "\n  ")
    end

    os.remove(errors)

    local file = io.open(path, "r")
    if not file then
        return nil, "the backup file was not written; refusing to remove anything"
    end
    local size = file:seek("end")
    file:close()

    if size < 1024 then
        return nil, "the backup is suspiciously small (" .. size
                 .. " bytes); refusing to remove anything"
    end

    return path, size
end
-- }}}

-- {{{ Retire.apply(handle, plan, state)
-- Take the backup, then run the whole deletion as one transaction.
function Retire.apply(handle, plan, state)
    local ColdHand = sibling(handle.neuron_root, "002-cold-hand.lua")
    local Receipts = sibling(handle.neuron_root, "006-receipts.lua")

    local receipt = Receipts.begin(handle, plan.operation, {
        roster     = plan.resolution.describes,
        characters = #plan.guids,
        tables     = plan.tables,
    })

    local backup_step = {
        hand      = "cold",
        describes = "back up " .. handle.db_characters .. " before removing anything",
    }

    local backup_path, size = Retire.backup(handle)
    if not backup_path then
        Receipts.record(receipt, backup_step, "failed", nil, size)
        Receipts.finish(receipt, "refused")
        Receipts.append(handle, receipt)
        return receipt
    end

    Receipts.record(receipt, backup_step, "done", nil,
        string.format("%s (%.1f MB)", backup_path, size / 1048576))
    receipt.backup = backup_path

    local delete_step = {
        hand      = "cold",
        describes = string.format("remove %d characters from %d tables, in one transaction",
            #plan.guids, plan.tables),
    }

    local output, why = ColdHand.script(handle, handle.db_characters,
        build_script(plan.guids), "retire")

    if not output then
        -- The transaction was never committed, so nothing changed. Saying that
        -- explicitly matters: the natural fear after a failed bulk delete is
        -- that it half happened.
        Receipts.record(receipt, delete_step, "failed", nil,
            why .. "\n  Nothing was committed; the world is unchanged.")
        Receipts.finish(receipt, "refused")
        Receipts.append(handle, receipt)
        return receipt
    end

    Receipts.record(receipt, delete_step, "done", nil, "committed")

    -- The guid list is recorded. It is not enough to restore anybody -- that is
    -- what the backup is for -- but it is an exact answer to "what did I remove".
    receipt.removed_guids = plan.guids

    Receipts.finish(receipt)
    Receipts.append(handle, receipt)
    return receipt
end
-- }}}

return Retire
