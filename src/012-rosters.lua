--------------------------------------------------------------------------------
-- 012-rosters.lua
--
-- A roster is a named set of characters, resolved at the moment it is used.
--
-- This is the lookup table the project was asked for -- "a teleport players
-- script which used a lookup table to teleport specific player id's toward a
-- desired location". The roster IS that table, and it belongs to the project
-- rather than to teleport, so every operation that acts on more than one
-- character is told who in the same way.
--
-- RESOLVED AT USE TIME, NEVER AT DEFINITION TIME. A roster defined as "bots
-- between 18 and 20" means different characters next week, and that is the
-- point. The alternative is a stored list that silently goes stale and then
-- moves the wrong forty people.
--
-- ORPHANS ARE EXCLUDED BY DEFAULT. The live deployment holds 900 characters with
-- no account row; they belong to nobody and cannot be logged in. A query roster
-- that did not exclude them would sweep them into every bulk operation, and
-- moving nine hundred abandoned characters is a slow way to find out they exist.
-- The exclusion is reported, never silent.
--
-- See issues/202-rosters.md for the blueprint.
--------------------------------------------------------------------------------

local Rosters = {}

-- {{{ sibling(neuron_root, filename)
local function sibling(neuron_root, filename)
    return dofile(neuron_root .. "/src/" .. filename)
end
-- }}}

-- {{{ CLASS_BY_NAME / RACE_BY_NAME
-- Reverse lookups so a query can say "hunters" instead of "class 3".
--
-- Dispatch tables keyed by the folded word. Built once from the forward tables
-- in the read layer, so there is exactly one place that knows class 3 is a
-- Hunter and it is not this file.
local function build_reverse(forward)
    local reverse = {}
    for id, name in pairs(forward) do
        local folded = name:lower():gsub("[^%a]", "")
        reverse[folded] = id
        -- Plural form, since a person asking for a group says "hunters".
        reverse[folded .. "s"] = id
    end
    return reverse
end
-- }}}

-- {{{ parse_query(text, WorldRead)
-- Turn a query string into a filter table.
--
-- The vocabulary is deliberately small and boring: level range, class, race,
-- bot or person, online or offline. It is a FILTER, not a language, and keeping
-- it one is what stops it growing into a second way of describing the world that
-- has to be maintained alongside the first.
--
-- Unrecognised words are an ERROR, not ignored. A query with a typo that
-- silently matches everything is how a roster resolves to twenty-five thousand
-- characters and somebody moves all of them.
local function parse_query(text, WorldRead)
    local classes = build_reverse(WorldRead.CLASSES)
    local races   = build_reverse(WorldRead.RACES)

    local filter = { include_orphans = false }
    local unknown = {}

    for word in text:gmatch("%S+") do
        local folded = word:lower()

        -- A level range: "18-20"
        local low, high = folded:match("^(%d+)%-(%d+)$")
        if low then
            filter.level_min, filter.level_max = tonumber(low), tonumber(high)

        -- A single level: "level20" or bare "20"
        elseif folded:match("^level(%d+)$") or folded:match("^%d+$") then
            local exact = tonumber(folded:match("(%d+)"))
            filter.level_min, filter.level_max = exact, exact

        elseif folded == "level" then
            -- A bare "level" preceding a range is noise; skip it so
            -- "level 18-20" reads naturally.

        elseif folded == "bot" or folded == "bots" then
            filter.is_bot = true
        elseif folded == "person" or folded == "people" or folded == "human" then
            filter.is_bot = false
        elseif folded == "online" then
            filter.online = true
        elseif folded == "offline" then
            filter.online = false
        elseif folded == "orphan" or folded == "orphans" then
            filter.orphans_only  = true
            filter.include_orphans = true

        elseif classes[folded] then
            filter.class = classes[folded]
        elseif races[folded] then
            filter.race = races[folded]

        else
            table.insert(unknown, word)
        end
    end

    if #unknown > 0 then
        return nil, "I do not understand " .. table.concat(unknown, ", ")
            .. " in a roster query. Understood: a level or level range (20, 18-20), "
            .. "a class, a race, bot/person, online/offline, orphans."
    end

    return filter
end
-- }}}

-- {{{ build_conditions(handle, filter)
-- Turn a filter into a WHERE fragment plus its bind values.
--
-- Everything is a bind value; nothing is pasted. A class id coming from our own
-- table could safely be concatenated, and it is bound anyway, because the moment
-- one value is pasted the next person adds a second one from somewhere else.
local function build_conditions(handle, filter)
    local conditions, binds = {}, {}

    local function add(sql, value)
        table.insert(conditions, sql)
        if value ~= nil then
            table.insert(binds, value)
        end
    end

    if filter.level_min then add("c.level >= ?", filter.level_min) end
    if filter.level_max then add("c.level <= ?", filter.level_max) end
    if filter.class    then add("c.class = ?",   filter.class)     end
    if filter.race     then add("c.race = ?",    filter.race)      end
    if filter.online ~= nil then
        add("c.online = ?", filter.online and 1 or 0)
    end

    -- The three character kinds, expressed against the account join.
    if filter.orphans_only then
        add("a.id IS NULL")
    else
        if not filter.include_orphans then
            add("a.id IS NOT NULL")
        end
        if filter.is_bot == true then
            add("a.username LIKE ?", handle.bot_account_prefix .. "%")
        elseif filter.is_bot == false then
            add("a.username NOT LIKE ?", handle.bot_account_prefix .. "%")
        end
    end

    return conditions, binds
end
-- }}}

-- {{{ Rosters.resolve(handle, specification, options)
-- Resolve a roster specification into characters.
--
-- Returns a resolution table:
--   characters  the resolved list
--   missing     names that matched nothing
--   excluded    how many orphans were filtered out, and why
--   describes   one line naming what was asked for
--
-- Two shapes of specification, told apart by whether it looks like a list of
-- names. A comma is the signal, because a name cannot contain one and a query
-- never needs one.
function Rosters.resolve(handle, specification, options)
    options = options or {}

    local WorldRead = sibling(handle.neuron_root, "005-world-read.lua")
    local ColdHand  = sibling(handle.neuron_root, "002-cold-hand.lua")

    specification = tostring(specification or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if specification == "" then
        return nil, "an empty roster names nobody"
    end

    -- A name list: comma-separated, or a single bare word that is a real
    -- character name. The bare-word case is checked against the database rather
    -- than guessed at, so "Grast" finds a character and "hunters" does not.
    local looks_like_names = specification:find(",", 1, true) ~= nil

    if not looks_like_names and not specification:find("%s") then
        local found = WorldRead.character_by_name(handle, specification)
        if found then
            return {
                characters = { found },
                missing    = {},
                excluded   = 0,
                describes  = "the character " .. found.name,
            }
        end
        -- Not a character name; fall through and read it as a query.
    end

    if looks_like_names then
        local names = {}
        for name in specification:gmatch("[^,]+") do
            name = name:gsub("^%s+", ""):gsub("%s+$", "")
            if name ~= "" then
                table.insert(names, name)
            end
        end

        local characters, missing = WorldRead.characters_by_name(handle, names)
        if not characters then
            return nil, missing
        end

        return {
            characters = characters,
            missing    = missing,
            excluded   = 0,
            describes  = string.format("%d named character%s",
                #names, #names == 1 and "" or "s"),
        }
    end

    -- Otherwise it is a query.
    local filter, why = parse_query(specification, WorldRead)
    if not filter then
        return nil, why
    end

    if options.include_orphans then
        filter.include_orphans = true
    end

    local conditions, binds = build_conditions(handle, filter)

    local where = ""
    if #conditions > 0 then
        where = "WHERE " .. table.concat(conditions, " AND ") .. " "
    end

    -- A hard ceiling. Twenty-five thousand characters exist, and a query with a
    -- typo in its filter could resolve to all of them. The limit is applied and
    -- REPORTED, so a roster that hit it is visibly truncated rather than quietly
    -- complete.
    local ceiling = options.limit or 200

    local rows, read_why = ColdHand.read(handle, handle.db_characters,
        "SELECT c.guid, c.name, c.account, c.race, c.class, c.gender, c.level, "
        .. "c.online, c.map, c.zone, c.position_x, c.position_y, c.position_z, "
        .. "c.orientation, a.username AS account_name "
        .. "FROM characters c LEFT JOIN " .. handle.db_auth .. ".account a "
        .. "ON a.id = c.account " .. where
        .. "ORDER BY c.name LIMIT " .. tonumber(ceiling + 1),
        binds)

    if not rows then
        return nil, read_why
    end

    local truncated = false
    if #rows > ceiling then
        truncated = true
        rows[#rows] = nil
    end

    -- Reuse the read layer's record shape rather than building a second one, so
    -- a roster member and a character read any other way are the same thing.
    local characters = {}
    for _, row in ipairs(rows) do
        local prefix = handle.bot_account_prefix
        local account_name = row.account_name and tostring(row.account_name) or nil
        table.insert(characters, {
            guid = tonumber(row.guid), name = row.name,
            account = tonumber(row.account), account_name = account_name,
            is_bot = account_name ~= nil and account_name:sub(1, #prefix) == prefix,
            race = tonumber(row.race), class = tonumber(row.class),
            gender = tonumber(row.gender), level = tonumber(row.level),
            race_name = WorldRead.RACES[tonumber(row.race)],
            class_name = WorldRead.CLASSES[tonumber(row.class)],
            gender_name = WorldRead.GENDERS[tonumber(row.gender)],
            online = tonumber(row.online) == 1,
            map = tonumber(row.map), zone = tonumber(row.zone),
            x = tonumber(row.position_x), y = tonumber(row.position_y),
            z = tonumber(row.position_z), o = tonumber(row.orientation),
            position_is_stale = tonumber(row.online) == 1,
        })
    end

    return {
        characters = characters,
        missing    = {},
        excluded   = filter.include_orphans and 0 or nil,
        truncated  = truncated,
        ceiling    = ceiling,
        describes  = "characters matching '" .. specification .. "'",
    }
end
-- }}}

-- {{{ Rosters.describe(resolution)
-- A resolution, rendered for a person, including what was NOT included.
--
-- The missing and truncated lines are the important ones. A roster that quietly
-- resolved to fewer characters than asked for is how an operation reports
-- success having done most of a job.
function Rosters.describe(resolution)
    local lines = {}
    table.insert(lines, string.format("%d character%s -- %s",
        #resolution.characters,
        #resolution.characters == 1 and "" or "s",
        resolution.describes))

    if #resolution.missing > 0 then
        table.insert(lines, "MISSING: no character named "
            .. table.concat(resolution.missing, ", "))
    end

    if resolution.truncated then
        table.insert(lines, string.format(
            "TRUNCATED at %d. More characters match than that; narrow the query "
            .. "or raise the limit deliberately.", resolution.ceiling))
    end

    if resolution.excluded == nil then
        table.insert(lines,
            "note: characters with no account row were excluded (add 'orphans' to include)")
    end

    return table.concat(lines, "\n")
end
-- }}}

return Rosters
