--------------------------------------------------------------------------------
-- 005-world-read.lua
--
-- Turns database rows into the small number of record types the rest of the
-- project talks about. Operations ask for "the characters in this roster" and
-- get records back; no operation anywhere writes a SELECT.
--
-- This is the generation/viewing split the project keeps everywhere: this file
-- produces data, operations consume it, and neither knows how the other works.
--
-- ONE FIELD MATTERS MORE THAN THE REST. Every character record carries `online`,
-- whether or not the caller asked, because forgetting to read it is exactly the
-- mistake 004-liveness.lua exists to prevent. It is not optional and it is not
-- lazy-loaded.
--
-- POSITION IS A CLAIM, NOT A FACT. For an OFFLINE character the row is
-- authoritative; nothing else holds their position. For an ONLINE character the
-- row is a stale snapshot from the last save, and the real position is in the
-- worldserver's memory. Records carry `position_is_stale` so a caller reasoning
-- about where somebody actually is cannot forget which case it has.
--
-- See issues/105-reading-the-world.md for the blueprint.
--------------------------------------------------------------------------------

local WorldRead = {}

-- {{{ sibling(neuron_root, filename)
local function sibling(neuron_root, filename)
    return dofile(neuron_root .. "/src/" .. filename)
end
-- }}}

-- {{{ RACES / CLASSES / GENDERS / MAPS
-- Dispatch tables rather than if-else chains, per the standing project
-- position: referring to data by index is cheaper than walking comparisons, and
-- a table is a thing you can print, count, and check for holes.
--
-- The gaps are real and meaningful. Race 9 is the pre-Cataclysm Goblin slot,
-- reserved and unused in 3.3.5a. Class 10 does not exist. A nil lookup here
-- means "this game has no such thing", which is different from "we forgot".
WorldRead.RACES = {
    [1]  = "Human",     [2]  = "Orc",    [3]  = "Dwarf", [4] = "Night Elf",
    [5]  = "Undead",    [6]  = "Tauren", [7]  = "Gnome", [8] = "Troll",
    [10] = "Blood Elf", [11] = "Draenei",
}

WorldRead.CLASSES = {
    [1] = "Warrior", [2] = "Paladin", [3]  = "Hunter",  [4] = "Rogue",
    [5] = "Priest",  [6] = "Death Knight", [7] = "Shaman",
    [8] = "Mage",    [9] = "Warlock", [11] = "Druid",
}

WorldRead.GENDERS = { [0] = "male", [1] = "female" }

WorldRead.MAPS = {
    [0]   = "Eastern Kingdoms",
    [1]   = "Kalimdor",
    [530] = "Outland",
    [571] = "Northrend",
}
-- }}}

-- {{{ CHARACTER_COLUMNS
-- The exact columns a character record is built from, in one place, so the
-- SELECT and the record shape cannot drift apart.
--
-- Aliased to `c` because every character read joins the auth database for the
-- account name, and `guid` is a column in both tables.
local CHARACTER_COLUMNS =
    "c.guid, c.name, c.account, c.race, c.class, c.gender, c.level, c.online, "
 .. "c.map, c.zone, c.position_x, c.position_y, c.position_z, c.orientation, "
 .. "a.username AS account_name"
-- }}}

-- {{{ character_source(handle)
-- The FROM clause every character read shares.
--
-- The join reaches into the AUTH database, which is deliberately not
-- profile-suffixed: accounts are shared across every profile on the machine,
-- which is why a bot account created for one profile is visible from all of
-- them.
--
-- LEFT rather than INNER. A character whose account row has been deleted is
-- orphaned data, and orphaned data should stay readable so somebody can find it
-- and decide what to do about it -- an inner join would make it vanish from
-- every query in the project, which is how orphans go unnoticed for years.
local function character_source(handle)
    return " FROM characters c LEFT JOIN " .. handle.db_auth
        .. ".account a ON a.id = c.account "
end
-- }}}

-- {{{ to_character(row, handle)
-- Map one database row onto a character record.
--
-- `online` is converted to a real Lua boolean here rather than left as the
-- database's 0/1. The reason is not tidiness: `if row.online then` is TRUE for
-- the number 0, so a caller that forgot to compare against 1 would treat every
-- offline character as online. Every guard would then misfire in the safe
-- direction, which is the kind of bug that hides for months.
local function to_character(row, handle)
    local online       = tonumber(row.online) == 1
    local account_name = row.account_name and tostring(row.account_name) or nil

    -- A HEURISTIC, not a recorded fact. Nothing in the schema says "this is a
    -- bot"; mod-playerbots simply creates its fleet under a configurable name
    -- prefix, and the live deployment has 2210 accounts under the default one.
    -- A person who names their account RNDBOTTLES would read as a bot. Stated
    -- plainly rather than hidden, because a wrong answer here silently puts a
    -- person into a roster meant for machines.
    local prefix = handle.bot_account_prefix
    local is_bot = account_name ~= nil
               and account_name:sub(1, #prefix) == prefix

    return {
        guid    = tonumber(row.guid),
        name    = row.name,
        account = tonumber(row.account),
        account_name = account_name,
        is_bot  = is_bot,

        race    = tonumber(row.race),
        class   = tonumber(row.class),
        gender  = tonumber(row.gender),
        level   = tonumber(row.level),

        race_name   = WorldRead.RACES[tonumber(row.race)],
        class_name  = WorldRead.CLASSES[tonumber(row.class)],
        gender_name = WorldRead.GENDERS[tonumber(row.gender)],

        online  = online,

        map     = tonumber(row.map),
        zone    = tonumber(row.zone),
        x       = tonumber(row.position_x),
        y       = tonumber(row.position_y),
        z       = tonumber(row.position_z),
        o       = tonumber(row.orientation),

        -- See the header note. An online character's stored coordinates are a
        -- snapshot from the last save; the live position is in server memory.
        position_is_stale = online,
    }
end
-- }}}

-- {{{ WorldRead.character_by_name(handle, name)
-- One character by name, or nil plus a reason.
--
-- Names are unique per realm and this deployment runs one realm, so a name is a
-- usable key for a person typing at a terminal. GUIDs remain the key for
-- anything the machine does, because a character can be renamed and a GUID
-- cannot.
function WorldRead.character_by_name(handle, name)
    local cold = sibling(handle.neuron_root, "002-cold-hand.lua")
    local rows, why = cold.read(handle, handle.db_characters,
        "SELECT " .. CHARACTER_COLUMNS .. character_source(handle) .. "WHERE c.name = ?",
        { name })

    if not rows then
        return nil, why
    end
    if #rows == 0 then
        return nil, "no character named '" .. tostring(name) .. "'"
    end
    return to_character(rows[1], handle)
end
-- }}}

-- {{{ WorldRead.characters_by_name(handle, names)
-- Several characters in ONE query.
--
-- The list forms exist so that a roster of forty is one round trip rather than
-- forty. That is the entire reason 002-cold-hand.lua exposes a placeholder-list
-- builder.
--
-- Names that matched nothing come back in `missing` rather than being silently
-- dropped. A caller asking for forty characters and receiving thirty-eight must
-- be told which two, or it moves thirty-eight people and reports success.
function WorldRead.characters_by_name(handle, names)
    if #names == 0 then
        return {}, {}
    end

    local cold = sibling(handle.neuron_root, "002-cold-hand.lua")
    local rows, why = cold.read(handle, handle.db_characters,
        "SELECT " .. CHARACTER_COLUMNS .. character_source(handle)
            .. "WHERE c.name IN (" .. cold.placeholders(#names) .. ") ORDER BY c.name",
        names)

    if not rows then
        return nil, why
    end

    local found, seen = {}, {}
    for _, row in ipairs(rows) do
        local character = to_character(row, handle)
        table.insert(found, character)
        seen[character.name] = true
    end

    local missing = {}
    for _, wanted in ipairs(names) do
        if not seen[wanted] then
            table.insert(missing, wanted)
        end
    end

    return found, missing
end
-- }}}

-- {{{ WorldRead.characters_by_guid(handle, guids)
-- The same, keyed by GUID. Used by anything replaying a receipt, since a
-- receipt records GUIDs -- a name in a receipt could have been given to a
-- different character since.
function WorldRead.characters_by_guid(handle, guids)
    if #guids == 0 then
        return {}, {}
    end

    local cold = sibling(handle.neuron_root, "002-cold-hand.lua")
    local rows, why = cold.read(handle, handle.db_characters,
        "SELECT " .. CHARACTER_COLUMNS .. character_source(handle)
            .. "WHERE c.guid IN (" .. cold.placeholders(#guids) .. ") ORDER BY c.name",
        guids)

    if not rows then
        return nil, why
    end

    local found, seen = {}, {}
    for _, row in ipairs(rows) do
        local character = to_character(row, handle)
        table.insert(found, character)
        seen[character.guid] = true
    end

    local missing = {}
    for _, wanted in ipairs(guids) do
        if not seen[tonumber(wanted)] then
            table.insert(missing, wanted)
        end
    end

    return found, missing
end
-- }}}

-- {{{ WorldRead.characters_online(handle)
-- Every character the database believes is logged in.
--
-- "believes" is doing work in that sentence. With the worldserver DOWN this flag
-- is whatever it was when the server stopped, and a server that crashed leaves
-- characters marked online forever. So the answer is only meaningful when the
-- world is up -- which the liveness guard already knows, because it only
-- consults this when the world is up.
function WorldRead.characters_online(handle)
    local cold = sibling(handle.neuron_root, "002-cold-hand.lua")
    local rows, why = cold.read(handle, handle.db_characters,
        "SELECT " .. CHARACTER_COLUMNS .. character_source(handle)
            .. "WHERE c.online = 1 ORDER BY c.name")

    if not rows then
        return nil, why
    end

    local characters = {}
    for _, row in ipairs(rows) do
        table.insert(characters, to_character(row, handle))
    end
    return characters
end
-- }}}

-- {{{ WorldRead.groups(handle)
-- Every party, with its members, regardless of login state.
--
-- `groups` is BACKTICKED because it is a reserved word in MySQL 8. Without the
-- backticks this query is a syntax error, and it is the kind that only shows up
-- against a live database -- the statement looks perfectly ordinary right up
-- until the server refuses it.
--
-- Two reads rather than a JOIN, joined in Lua, so member ordering stays under
-- our control: `subgroup` matters for raid layout later, and a flattening JOIN
-- loses it.
function WorldRead.groups(handle)
    local cold = sibling(handle.neuron_root, "002-cold-hand.lua")

    local group_rows, why = cold.read(handle, handle.db_characters,
        "SELECT guid, leaderGuid, lootMethod, difficulty FROM `groups` ORDER BY guid")
    if not group_rows then
        return nil, why
    end

    local member_rows, member_why = cold.read(handle, handle.db_characters,
        "SELECT guid, memberGuid, memberFlags, subgroup FROM group_member "
            .. "ORDER BY guid, subgroup")
    if not member_rows then
        return nil, member_why
    end

    local by_group = {}
    for _, row in ipairs(group_rows) do
        by_group[tonumber(row.guid)] = {
            guid        = tonumber(row.guid),
            leader_guid = tonumber(row.leaderGuid),
            members     = {},
        }
    end

    for _, row in ipairs(member_rows) do
        local group = by_group[tonumber(row.guid)]
        -- A member row whose group row is absent is orphaned data. Skipped
        -- rather than crashing; reporting it is a validator's job, not a
        -- reader's.
        if group then
            table.insert(group.members, {
                guid     = tonumber(row.memberGuid),
                subgroup = tonumber(row.subgroup),
            })
        end
    end

    local groups = {}
    for _, group in pairs(by_group) do
        table.insert(groups, group)
    end
    table.sort(groups, function(a, b) return a.guid < b.guid end)

    return groups
end
-- }}}

-- {{{ WorldRead.summary(handle)
-- The counts the status board prints.
--
-- This function IS the numbers. Per the standing project position, documentation
-- must not carry statistics -- "there are 25015 characters" is wrong the moment
-- somebody makes another one. Documents point here instead.
--
-- The bot count comes from the account-name prefix, which is a heuristic and is
-- described as such where it is applied in to_character. The LIKE pattern is a
-- BIND VALUE rather than pasted in, so a prefix containing a percent sign
-- cannot silently turn into a wildcard and count everything.
function WorldRead.summary(handle)
    local cold = sibling(handle.neuron_root, "002-cold-hand.lua")

    local rows, why = cold.read(handle, handle.db_characters,
        "SELECT"
     .. "  (SELECT COUNT(*) FROM characters)                  AS characters,"
     .. "  (SELECT COUNT(*) FROM characters WHERE online = 1) AS online,"
     .. "  (SELECT COUNT(*) FROM `groups`)                    AS parties,"
     .. "  (SELECT COUNT(DISTINCT account) FROM characters)   AS accounts,"
     .. "  (SELECT COUNT(*) FROM characters c JOIN " .. handle.db_auth .. ".account a"
     .. "     ON a.id = c.account WHERE a.username LIKE ?)    AS bots,"
     .. "  (SELECT COUNT(*) FROM characters c LEFT JOIN " .. handle.db_auth .. ".account a"
     .. "     ON a.id = c.account WHERE a.id IS NULL)         AS orphans",
        { handle.bot_account_prefix .. "%" })

    if not rows then
        return nil, why
    end
    if #rows == 0 then
        return nil, "the summary query returned no rows, which should be impossible"
    end

    local row = rows[1]
    return {
        characters = tonumber(row.characters),
        online     = tonumber(row.online),
        parties    = tonumber(row.parties),
        accounts   = tonumber(row.accounts),
        bots       = tonumber(row.bots),

        -- Orphans are counted SEPARATELY and never folded into either other
        -- number. A character whose account row has been deleted is neither a
        -- bot nor a person; it is residue. On the live deployment there are 900
        -- of them, and quietly counting them as people made the people count
        -- wrong by two orders of magnitude -- which is what a silent category
        -- error looks like from the outside: a number that is merely surprising
        -- rather than obviously broken.
        orphans    = tonumber(row.orphans),

        -- Characters on a real, existing, non-bot account. The only number here
        -- that means "somebody plays this".
        people     = tonumber(row.characters)
                     - tonumber(row.bots)
                     - tonumber(row.orphans),
    }
end
-- }}}


-- {{{ WorldRead.describe_character(character)
-- One character as a line a person can read.
--
-- Race and class print as words. A reader should never have to know that class 4
-- is a Rogue; the project's standing position is that naming a thing in English
-- beats naming it by its code.
function WorldRead.describe_character(character)
    local where = WorldRead.MAPS[character.map] or ("map " .. tostring(character.map))
    return string.format("%-14s %-3d %-10s %-13s %-7s %-4s %s%s",
        character.name,
        character.level,
        character.race_name  or ("race "  .. tostring(character.race)),
        character.class_name or ("class " .. tostring(character.class)),
        character.online and "online" or "offline",
        character.is_bot and "bot" or "you",
        where,
        character.position_is_stale and "  (position is a stale snapshot)" or "")
end
-- }}}

return WorldRead
