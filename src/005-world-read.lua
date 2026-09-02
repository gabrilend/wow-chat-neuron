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
-- whether or not the caller asked for it, because forgetting to read it is
-- exactly the mistake 004-liveness.lua exists to prevent. It is not optional and
-- it is not lazy-loaded.
--
-- POSITION IS A CLAIM, NOT A FACT. For an OFFLINE character the row is
-- authoritative; nothing else holds their position. For an ONLINE character the
-- row is a stale snapshot from the last save, and the real position is in the
-- worldserver's memory. Records therefore carry `position_is_stale` so a caller
-- reasoning about where somebody actually is cannot forget which case it has.
--
-- See issues/105-reading-the-world.md for the blueprint.
--------------------------------------------------------------------------------

local WorldRead = {}

-- {{{ sibling(neuron_root, filename)
local function sibling(neuron_root, filename)
    return dofile(neuron_root .. "/src/" .. filename)
end
-- }}}

-- {{{ RACES / CLASSES / GENDERS
-- Dispatch tables rather than if-else chains, per the standing project
-- position: referring to data by index is cheaper than walking comparisons, and
-- a table is a thing you can print, count, and check for holes.
--
-- The gaps are real and meaningful. Race 9 is the pre-Cataclysm Goblin slot,
-- reserved and unused in 3.3.5a. Class 10 does not exist. A nil lookup here
-- means "this game has no such thing", which is different from "we forgot".
WorldRead.RACES = {
    [1]  = "Human",   [2]  = "Orc",     [3]  = "Dwarf",  [4] = "Night Elf",
    [5]  = "Undead",  [6]  = "Tauren",  [7]  = "Gnome",  [8] = "Troll",
    [10] = "Blood Elf", [11] = "Draenei",
}

WorldRead.CLASSES = {
    [1] = "Warrior", [2] = "Paladin", [3]  = "Hunter",  [4] = "Rogue",
    [5] = "Priest",  [6] = "Death Knight", [7] = "Shaman",
    [8] = "Mage",    [9] = "Warlock", [11] = "Druid",
}

WorldRead.GENDERS = { [0] = "male", [1] = "female" }

-- Map ids. Only the four that exist as continents in 3.3.5a; instance maps are
-- numerous and are looked up from the world database when they are ever needed.
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
local CHARACTER_COLUMNS =
    "guid, name, account, race, class, gender, level, online, "
 .. "map, zone, position_x, position_y, position_z, orientation"
-- }}}

-- {{{ to_character(row)
-- Map one database row onto a character record.
--
-- `online` is converted to a real Lua boolean here rather than left as the
-- database's 0/1. The reason is not tidiness: `if row.online then` is TRUE for
-- the number 0, so a caller that forgot to compare against 1 would treat every
-- offline character as online and every guard would misfire in the safe
-- direction, which is the kind of bug that hides for months.
local function to_character(row)
    local online = tonumber(row.online) == 1
    return {
        guid    = tonumber(row.guid),
        name    = row.name,
        account = tonumber(row.account),

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
-- One character by name, or nil.
--
-- Names are unique per realm and this deployment runs one realm, so a name is a
-- usable key for a person typing at a terminal. GUIDs remain the key for
-- anything the machine does, because a character can be renamed and a GUID
-- cannot.
function WorldRead.character_by_name(handle, name)
    local cold = sibling(handle.neuron_root, "002-cold-hand.lua")
    local rows, why = cold.read(handle, handle.db_characters,
        "SELECT " .. CHARACTER_COLUMNS .. " FROM characters WHERE name = ?", { name })

    if not rows then
        return nil, why
    end
    if #rows == 0 then
        return nil, "no character named '" .. tostring(name) .. "'"
    end
    return to_character(rows[1])
end
-- }}}

-- {{{ WorldRead.characters_by_name(handle, names)
-- Several characters in ONE query.
--
-- The list forms exist so that a roster of forty is one round trip rather than
-- forty. That is the entire reason 002-cold-hand.lua exposes a placeholder-list
-- builder.
--
-- Names that matched nothing are returned separately rather than silently
-- dropped. A caller asking for forty characters and receiving thirty-eight must
-- be told which two are missing, or it will move thirty-eight people and report
-- success.
function WorldRead.characters_by_name(handle, names)
    if #names == 0 then
        return {}, {}
    end

    local cold = sibling(handle.neuron_root, "002-cold-hand.lua")
    local rows, why = cold.read(handle, handle.db_characters,
        "SELECT " .. CHARACTER_COLUMNS .. " FROM characters WHERE name IN ("
            .. cold.placeholders(#names) .. ") ORDER BY name",
        names)

    if not rows then
        return nil, why
    end

    local found, by_name = {}, {}
    for _, row in ipairs(rows) do
        local character = to_character(row)
        table.insert(found, character)
        by_name[character.name] = true
    end

    local missing = {}
    for _, wanted in ipairs(names) do
        if not by_name[wanted] then
            table.insert(missing, wanted)
        end
    end

    return found, missing
end
-- }}}

-- {{{ WorldRead.characters_online(handle)
-- Every character the database believes is logged in.
--
-- "believes" is doing work in that sentence. With the worldserver DOWN, this
-- flag is whatever it was when the server stopped -- a server that crashed
-- leaves characters marked online forever. So the answer is only meaningful
-- when the world is up, and callers that use it for the liveness guard already
-- know that, because the guard only consults it when the world is up.
function WorldRead.characters_online(handle)
    local cold = sibling(handle.neuron_root, "002-cold-hand.lua")
    local rows, why = cold.read(handle, handle.db_characters,
        "SELECT " .. CHARACTER_COLUMNS .. " FROM characters WHERE online = 1 ORDER BY name")

    if not rows then
        return nil, why
    end

    local characters = {}
    for _, row in ipairs(rows) do
        table.insert(characters, to_character(row))
    end
    return characters
end
-- }}}

-- {{{ WorldRead.groups(handle)
-- Every party, with its members, regardless of login state.
--
-- Two tables: `groups` holds the party and its leader, `group_member` holds one
-- row per member. Reading both and joining in Lua rather than in SQL keeps the
-- member ordering under our control -- `subgroup` and `memberFlags` matter for
-- raid layout later, and a JOIN that flattens them loses that.
function WorldRead.groups(handle)
    local cold = sibling(handle.neuron_root, "002-cold-hand.lua")

    local group_rows, why = cold.read(handle, handle.db_characters,
        "SELECT guid, leaderGuid, lootMethod, difficulty FROM groups ORDER BY guid")
    if not group_rows then
        return nil, why
    end

    local member_rows, member_why = cold.read(handle, handle.db_characters,
        "SELECT guid, memberGuid, memberFlags, subgroup FROM group_member ORDER BY guid, subgroup")
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
        -- A member row whose group row is absent is orphaned data. It is
        -- skipped rather than crashing, and it is worth knowing about -- but
        -- reporting it is the validator's job, not this reader's.
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
-- must not carry statistics -- "there are 214 characters" is wrong the moment
-- somebody makes another one. Documents point here instead.
function WorldRead.summary(handle)
    local cold = sibling(handle.neuron_root, "002-cold-hand.lua")

    local rows, why = cold.read(handle, handle.db_characters, [[
        SELECT
            (SELECT COUNT(*) FROM characters)               AS characters,
            (SELECT COUNT(*) FROM characters WHERE online=1) AS online,
            (SELECT COUNT(*) FROM `groups`)                  AS parties,
            (SELECT COUNT(DISTINCT account) FROM characters)  AS accounts
    ]])

    if not rows then
        return nil, why
    end
    if #rows == 0 then
        return nil, "the summary query returned no rows, which should be impossible"
    end

    return {
        characters = tonumber(rows[1].characters),
        online     = tonumber(rows[1].online),
        parties    = tonumber(rows[1].parties),
        accounts   = tonumber(rows[1].accounts),
    }
end
-- }}}

-- {{{ WorldRead.describe_character(character)
-- One character as a line a person can read.
--
-- Race and class are printed as words. A reader should never have to know that
-- class 4 is a Rogue, and the project's standing position is that naming a
-- thing in English beats naming it by its code.
function WorldRead.describe_character(character)
    local where = WorldRead.MAPS[character.map] or ("map " .. tostring(character.map))
    return string.format("%-14s %-3d %-10s %-10s %-7s %s%s",
        character.name,
        character.level,
        character.race_name  or ("race " .. tostring(character.race)),
        character.class_name or ("class " .. tostring(character.class)),
        character.online and "online" or "offline",
        where,
        character.position_is_stale and "  (position is a stale snapshot)" or "")
end
-- }}}

return WorldRead
