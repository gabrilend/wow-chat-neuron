--------------------------------------------------------------------------------
-- 018-bestiary.lua
--
-- `world.creatures` -- what kinds of thing can be in the world, and which of
-- them suit a given level.
--
-- The first READ in the project to carry a declaration, which makes it the
-- first word a model can use to LOOK at anything. Before it, every registered
-- operation changed something: a model could act on the world and could not
-- examine it.
--
-- It reads creature_template, the catalogue of every kind of creature the game
-- knows. Not the `creature` table -- that is where individuals stand. This one
-- is the species list.
--------------------------------------------------------------------------------

local Bestiary = {}

-- {{{ sibling(neuron_root, filename)
local function sibling(neuron_root, filename)
    return dofile(neuron_root .. "/src/" .. filename)
end
-- }}}

-- {{{ Bestiary.declaration
Bestiary.declaration = {
    name    = "world.creatures",
    summary = "List kinds of creature by type and level band, for choosing "
           .. "something to spawn.",
    kind    = "read",
    hands   = { "cold" },
    params  = {
        { name = "type", type = "string", required = false,
          describes = "What kind of creature: undead, beast, humanoid, demon, "
                   .. "dragonkin, elemental, giant, mechanical. Leave it out "
                   .. "for any kind." },
        { name = "level", type = "integer", required = false,
          describes = "A character level. Returns creatures whose own level "
                   .. "band contains it -- so 12 finds things built to fight a "
                   .. "level 12 player, not things whose level is exactly 12." },
        { name = "name", type = "string", required = false,
          describes = "Part of a creature's name, such as 'skeleton'. Matched "
                   .. "anywhere in the name, ignoring case." },
        { name = "rank", type = "string", required = false,
          describes = "How much of a fight: normal, elite, rare_elite, rare, "
                   .. "world_boss. Leave it out for ordinary creatures only." },
        { name = "limit", type = "integer", required = false, default = 25,
          describes = "How many to return. Keep it small -- this table holds "
                   .. "tens of thousands of rows." },
    },
}
-- }}}

-- {{{ FIGHTABLE
-- What the bestiary will return when nobody asked for something specific.
--
-- creature_template holds every row the game has, and most of them are not
-- creatures in any sense a person means: invisible quest triggers, scenery,
-- spell targets, and thousands of rows with no model at all. Handing that list
-- to a model produces an encounter with a squirrel, or with something that does
-- not render.
--
-- Three filters do almost all the work:
--
--   modelid1 > 0     it has something to look like
--   type is fightable  not a critter, totem, pet, gas cloud, or "not specified"
--   minlevel > 0     it has a level band at all
--
-- This is a heuristic and it is stated as one. It will exclude things somebody
-- eventually wants and include things nobody does, and when that happens the
-- fix is here rather than in whatever was surprised by it.
local FIGHTABLE = "modelid1 > 0 AND minlevel > 0"
-- }}}

-- {{{ Bestiary.find(handle, args)
-- The read itself. Returns rows; renders nothing.
function Bestiary.find(handle, args)
    args = args or {}

    local cold  = sibling(handle.neuron_root, "002-cold-hand.lua")
    local Types = sibling(handle.neuron_root, "017-creature-types.lua")

    local where, binds = { FIGHTABLE }, {}

    -- {{{ type
    if args.type then
        local kind, why = Types.kind.of(tostring(args.type):lower())
        if not kind then
            return nil, "world.creatures: " .. why
        end
        table.insert(where, "type = ?")
        table.insert(binds, kind.id)
    else
        -- No type asked for means every FIGHTABLE type, listed explicitly
        -- rather than as "not the others" -- an IN clause of eight numbers is
        -- one index scan, and a NOT IN of five is a table scan that also lets
        -- through any new type the game adds.
        local fightable = {}
        for _, kind in ipairs(Types.kind.members) do
            if kind.fightable then table.insert(fightable, kind.id) end
        end
        table.insert(where, "type IN (" .. cold.placeholders(#fightable) .. ")")
        for _, id in ipairs(fightable) do table.insert(binds, id) end
    end
    -- }}}

    -- {{{ level
    -- A template has a BAND, so a level is inside it or it is not. Asking
    -- `minlevel = ?` instead returns almost nothing and reads as an empty
    -- database rather than as the wrong question.
    if args.level then
        local level = tonumber(args.level)
        if not level then
            return nil, string.format(
                "world.creatures: level must be a number, got '%s'.",
                tostring(args.level))
        end
        table.insert(where, "minlevel <= ? AND maxlevel >= ?")
        table.insert(binds, math.floor(level))
        table.insert(binds, math.floor(level))
    end
    -- }}}

    -- {{{ rank
    if args.rank then
        local rank, why = Types.rank.of(tostring(args.rank):lower())
        if not rank then
            return nil, "world.creatures: " .. why
        end
        table.insert(where, "rank = ?")
        table.insert(binds, rank.id)
    else
        -- Ordinary creatures unless asked otherwise. A level band full of world
        -- bosses is not a level band.
        table.insert(where, "rank = 0")
    end
    -- }}}

    -- {{{ name
    if args.name and args.name ~= "" then
        table.insert(where, "name LIKE ?")
        table.insert(binds, "%" .. tostring(args.name) .. "%")
    end
    -- }}}

    local limit = math.floor(tonumber(args.limit) or 25)
    if limit < 1 then limit = 1 end
    if limit > 200 then limit = 200 end

    local statement =
        "SELECT entry, name, subname, minlevel, maxlevel, type, rank, faction "
     .. "FROM creature_template WHERE " .. table.concat(where, " AND ")
     .. " ORDER BY minlevel, name LIMIT " .. limit

    local rows, why = cold.read(handle, handle.db_world, statement, binds)
    if not rows then
        return nil, string.format(
            "world.creatures could not read the bestiary.\n"
         .. "  %s\n"
         .. "  Read: nothing. The filters were: %s\n"
         .. "  To debug: is the world database up? `scripts/status` distinguishes\n"
         .. "  a missing socket from a stale one.", why, table.concat(where, " AND "))
    end

    local found = {}
    for _, row in ipairs(rows) do
        local kind = Types.by_id(Types.kind, tonumber(row.type))
        local rank = Types.by_id(Types.rank, tonumber(row.rank))

        table.insert(found, {
            entry    = tonumber(row.entry),
            name     = row.name,
            subname  = row.subname ~= "" and row.subname or nil,
            minlevel = tonumber(row.minlevel),
            maxlevel = tonumber(row.maxlevel),
            kind     = kind and kind.name or ("type " .. tostring(row.type)),
            rank     = rank and rank.name or ("rank " .. tostring(row.rank)),
            worth    = rank and rank.worth or 1,
            faction  = tonumber(row.faction),
        })
    end

    return found
end
-- }}}

-- {{{ Bestiary.run(handle, args)
-- What the registry calls. A read has no plan and no apply: it runs, and its
-- answer IS the result.
function Bestiary.run(handle, args)
    local found, why = Bestiary.find(handle, args)
    if not found then return nil, why end

    return {
        creatures = found,
        describes = Bestiary.describe(found, args),
    }
end
-- }}}

-- {{{ Bestiary.describe(found, args)
-- Rows as lines. Separate from the reading, so the same answer can be rendered
-- for a terminal, for the chat window, and as a tool result without any of them
-- being the one true format.
function Bestiary.describe(found, args)
    if #found == 0 then
        return string.format(
            "nothing matches%s%s%s.\n"
         .. "  The bestiary only returns creatures that have a model, a level\n"
         .. "  band, and a type that can fight -- most of creature_template is\n"
         .. "  scenery and quest triggers. Try a wider level, or no type.",
            args.type  and (" type " .. args.type)      or "",
            args.level and (" at level " .. args.level) or "",
            args.name  and (" named like '" .. args.name .. "'") or "")
    end

    local lines = {}
    for _, creature in ipairs(found) do
        table.insert(lines, string.format("  %6d  %-32s %2d-%-2d  %-10s %s",
            creature.entry,
            creature.name .. (creature.subname and (" <" .. creature.subname .. ">") or ""),
            creature.minlevel, creature.maxlevel,
            creature.kind, creature.rank))
    end

    return string.format("%d creature kind%s:\n%s",
        #found, #found == 1 and "" or "s", table.concat(lines, "\n"))
end
-- }}}

return Bestiary
