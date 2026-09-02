--------------------------------------------------------------------------------
-- 011-place-book.lua
--
-- Places have names. `ratchet`, `menethil-harbor`, `the-ridge`. A name resolves
-- to a map, three coordinates, an orientation, and a sentence about what it is.
--
-- MOST OF IT ALREADY EXISTS. The world database ships `game_tele` -- 1,989 named
-- locations on the live deployment -- and that is the table AzerothCore's own
-- teleport command reads.
--
-- Which produces the symmetry that shapes all of phase 2: the live hand's
-- `tele name <character> <location>` takes EXACTLY these names. One name works
-- through both hands, differently --
--
--   live : passes the name straight through to the game master command
--   cold : looks up the coordinates and writes them onto the character row
--
-- -- with no translation layer and no mapping table, so the two hands cannot
-- disagree about where `ratchet` is unless the database disagrees with itself.
--
-- See issues/201-the-place-book.md for the blueprint.
--------------------------------------------------------------------------------

local PlaceBook = {}

-- {{{ sibling(neuron_root, filename)
local function sibling(neuron_root, filename)
    return dofile(neuron_root .. "/src/" .. filename)
end
-- }}}

-- {{{ normalise(name)
-- Fold a name to its comparable form.
--
-- The game's names are `MenethilHarbor`, `TheBarrens` -- camel-cased and
-- unspaced. Nobody types that. Lowercasing and stripping everything that is not
-- a letter or digit makes `menethil harbor`, `Menethil-Harbor`, and
-- `menethilharbor` all find the same row.
--
-- Used on BOTH sides of every comparison, and it must be the same function on
-- both sides. Two normalisers that drift apart produce a lookup that works in a
-- test and not in life.
local function normalise(name)
    return (tostring(name):lower():gsub("[^%a%d]", ""))
end

PlaceBook.normalise = normalise
-- }}}

-- {{{ INSTANCE_CONTINENTS
-- The maps that are open world. Everything else in `game_tele` is an instance.
--
-- This matters because writing an OFFLINE character's row to an instance map is
-- likely to produce a character who cannot log in -- the server expects an
-- instance binding that does not exist. Teleporting there is a guarded action,
-- not a forbidden one, but the guard needs to know which is which.
local OPEN_WORLD_MAPS = {
    [0]   = "Eastern Kingdoms",
    [1]   = "Kalimdor",
    [530] = "Outland",
    [571] = "Northrend",
}

PlaceBook.OPEN_WORLD_MAPS = OPEN_WORLD_MAPS
-- }}}

-- {{{ to_place(row, known_to_game)
-- Map a database row onto a place record.
--
-- `known_to_game` is the field the teleport operation branches on. A place the
-- game knows can be reached with `tele name`; a project-only place cannot, and
-- must go through coordinates. Carrying that on the place rather than
-- recomputing it means no caller has to remember the rule.
local function to_place(row, known_to_game)
    local map = tonumber(row.map)
    return {
        name          = row.name,
        map           = map,
        map_name      = OPEN_WORLD_MAPS[map],
        is_open_world = OPEN_WORLD_MAPS[map] ~= nil,
        x             = tonumber(row.position_x),
        y             = tonumber(row.position_y),
        z             = tonumber(row.position_z),
        o             = tonumber(row.orientation),
        known_to_game = known_to_game,
    }
end
-- }}}

-- {{{ PlaceBook.ensure_table(handle)
-- Create the project's own place table if it is not there.
--
-- It lives in the CHARACTERS database rather than the world database. The world
-- database is regenerated wholesale when a deployment re-imports upstream data;
-- the characters database is not. A project table in the world database is a
-- table that vanishes the next time somebody updates the server.
--
-- The name is prefixed so that neuron's rows are unmistakably neuron's, and so
-- that a person looking at an unfamiliar table can tell who put it there.
function PlaceBook.ensure_table(handle)
    local cold = sibling(handle.neuron_root, "002-cold-hand.lua")
    return cold.write(handle, handle.db_characters, [[
        CREATE TABLE IF NOT EXISTS neuron_place (
            name        VARCHAR(100) NOT NULL,
            map         INT UNSIGNED NOT NULL,
            position_x  FLOAT NOT NULL,
            position_y  FLOAT NOT NULL,
            position_z  FLOAT NOT NULL,
            orientation FLOAT NOT NULL DEFAULT 0,
            describes   VARCHAR(255) NOT NULL DEFAULT '',
            created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (name)
        ) DEFAULT CHARSET=utf8mb4
    ]])
end
-- }}}

-- {{{ PlaceBook.resolve(handle, name)
-- Find a place by name. Returns the place, or nil plus a message.
--
-- Resolution order is PROJECT FIRST, then the game, so a project place may
-- shadow a game one deliberately. Shadowing is reported rather than silent,
-- because quietly getting a different Ratchet than the game means is exactly the
-- sort of thing that costs somebody an hour.
--
-- An AMBIGUOUS match returns every candidate rather than picking one. There are
-- 1,989 names and many share prefixes; guessing which was meant and then moving
-- forty characters there is not a recoverable mistake.
function PlaceBook.resolve(handle, name)
    local cold   = sibling(handle.neuron_root, "002-cold-hand.lua")
    local wanted = normalise(name)

    -- Project places first. Read them all: the table is small by construction,
    -- and normalising in Lua keeps the fold rule in exactly one place rather
    -- than duplicating it as a SQL expression that could drift from it.
    local project_rows = cold.read(handle, handle.db_characters,
        "SELECT name, map, position_x, position_y, position_z, orientation, describes "
        .. "FROM neuron_place")

    local project_exact = {}
    for _, row in ipairs(project_rows or {}) do
        if normalise(row.name) == wanted then
            table.insert(project_exact, row)
        end
    end

    if #project_exact == 1 then
        local place = to_place(project_exact[1], false)
        place.describes = project_exact[1].describes
        return place
    elseif #project_exact > 1 then
        return nil, "several project places normalise to '" .. name .. "'"
    end

    -- Then the game's own table.
    local game_rows, why = cold.read(handle, handle.db_world,
        "SELECT name, map, position_x, position_y, position_z, orientation FROM game_tele")
    if not game_rows then
        return nil, why
    end

    local exact, partial = {}, {}
    for _, row in ipairs(game_rows) do
        local folded = normalise(row.name)
        if folded == wanted then
            table.insert(exact, row)
        elseif folded:find(wanted, 1, true) then
            table.insert(partial, row)
        end
    end

    if #exact == 1 then
        return to_place(exact[1], true)
    end

    if #exact > 1 then
        local names = {}
        for _, row in ipairs(exact) do table.insert(names, row.name) end
        return nil, "'" .. name .. "' matches several places exactly: "
                 .. table.concat(names, ", ")
    end

    -- No exact match. A single partial is accepted -- typing "ratchet" for
    -- "Ratchet" should work -- but several partials are reported in full rather
    -- than resolved by guessing.
    if #partial == 1 then
        return to_place(partial[1], true)
    end

    if #partial > 1 then
        local names = {}
        for index, row in ipairs(partial) do
            if index > 12 then
                table.insert(names, string.format("... and %d more", #partial - 12))
                break
            end
            table.insert(names, row.name)
        end
        return nil, "'" .. name .. "' is ambiguous -- " .. #partial
                 .. " places contain it: " .. table.concat(names, ", ")
    end

    return nil, "no place called '" .. name .. "'"
end
-- }}}

-- {{{ PlaceBook.search(handle, fragment, limit)
-- List places whose names contain a fragment. For a person hunting a name.
function PlaceBook.search(handle, fragment, limit)
    local cold   = sibling(handle.neuron_root, "002-cold-hand.lua")
    local wanted = normalise(fragment or "")

    local rows, why = cold.read(handle, handle.db_world,
        "SELECT name, map, position_x, position_y, position_z, orientation FROM game_tele "
        .. "ORDER BY name")
    if not rows then
        return nil, why
    end

    local found = {}
    for _, row in ipairs(rows) do
        if wanted == "" or normalise(row.name):find(wanted, 1, true) then
            table.insert(found, to_place(row, true))
            if limit and #found >= limit then
                break
            end
        end
    end

    return found
end
-- }}}

-- {{{ PlaceBook.remember(handle, name, character, describes)
-- Capture a character's current position as a named project place.
--
-- This is how `the-ridge` comes to exist: you stand on it and name it.
--
-- The character's stored position is used, which means for an ONLINE character
-- this records where they were at the last save rather than where they are
-- standing now. That is stated on the returned place so a caller can warn, and
-- it is the same staleness every other reader of a live character's position
-- has to live with.
function PlaceBook.remember(handle, name, character, describes)
    local cold = sibling(handle.neuron_root, "002-cold-hand.lua")

    local ok, why = PlaceBook.ensure_table(handle)
    if not ok then
        return nil, why
    end

    local affected, write_why = cold.write(handle, handle.db_characters,
        "REPLACE INTO neuron_place "
        .. "(name, map, position_x, position_y, position_z, orientation, describes) "
        .. "VALUES (?, ?, ?, ?, ?, ?, ?)",
        { name, character.map, character.x, character.y, character.z,
          character.o, describes or "" })

    if not affected then
        return nil, write_why
    end

    return {
        name          = name,
        map           = character.map,
        map_name      = OPEN_WORLD_MAPS[character.map],
        is_open_world = OPEN_WORLD_MAPS[character.map] ~= nil,
        x = character.x, y = character.y, z = character.z, o = character.o,
        known_to_game = false,
        describes     = describes or "",
        from_stale_position = character.position_is_stale,
    }
end
-- }}}

-- {{{ PlaceBook.describe(place)
-- One place, rendered for a person.
function PlaceBook.describe(place)
    local where = place.map_name or ("map " .. tostring(place.map))
    local origin = place.known_to_game and "game" or "project"
    return string.format("%-24s %-18s %9.1f %9.1f %7.1f  [%s]",
        place.name, where, place.x, place.y, place.z, origin)
end
-- }}}

return PlaceBook
