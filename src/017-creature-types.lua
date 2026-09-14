--------------------------------------------------------------------------------
-- 017-creature-types.lua
--
-- What kind of thing a creature is, and how dangerous, as two enums.
--
-- Read out of the deployment's own source rather than remembered:
--
--     source-beta/src/server/shared/SharedDefines.h:2620   enum CreatureType
--     source-beta/src/server/shared/SharedDefines.h:2962   enum CreatureEliteType
--
-- Verified 2026-09-04. Re-check after an upstream update with:
--
--     grep -n -A16 "^enum CreatureType" \
--       <deployment>/source-beta/src/server/shared/SharedDefines.h
--
-- A wrong type number does not error. It returns beasts when somebody asked for
-- undead, and the answer looks perfectly reasonable.
--
-- Kept here beside the bestiary rather than in src/025-enums/ because these
-- words mean something to creature_template and to nothing else. The enums in
-- that directory -- hands, kinds, refusals -- are the project's own bones.
--------------------------------------------------------------------------------

local here = debug.getinfo(1, "S").source:match("^@(.*/)")
local Load = dofile(here .. "024-load.lua")
local Enum = Load(here .. "025-enums/026-enum.lua")

local CreatureTypes = {}

-- {{{ CreatureTypes.kind
-- `creature_template.type`. Note that the numbering starts at 1 and that 10 is
-- "not specified" rather than a gap -- unlike the class list, where 10 is
-- genuinely nothing.
--
-- `fightable` is this project's judgment rather than the game's, and it is a
-- judgment the bestiary needs: creature_template holds tens of thousands of
-- rows and most of them are quest props, invisible triggers and scenery. A
-- model handed the raw list picks a critter or a totem, spawns it, and produces
-- an encounter with a squirrel.
CreatureTypes.kind = Enum.define("CreatureTypes", {
    { "beast",         id =  1, fightable = true  },
    { "dragonkin",     id =  2, fightable = true  },
    { "demon",         id =  3, fightable = true  },
    { "elemental",     id =  4, fightable = true  },
    { "giant",         id =  5, fightable = true  },
    { "undead",        id =  6, fightable = true  },
    { "humanoid",      id =  7, fightable = true  },
    -- Critters have one health and die to a sneeze. Not an encounter.
    { "critter",       id =  8, fightable = false },
    { "mechanical",    id =  9, fightable = true  },
    -- Where most of the scenery and the quest triggers live.
    { "not_specified", id = 10, fightable = false },
    { "totem",         id = 11, fightable = false },
    { "non_combat_pet",id = 12, fightable = false },
    { "gas_cloud",     id = 13, fightable = false },
})
-- }}}

-- {{{ CreatureTypes.rank
-- `creature_template.rank`. A normal creature and an elite of the same level
-- are very different fights, which is why a request for "successive encounters,
-- level progressing" that ignored rank would produce a smooth level curve and a
-- wildly uneven difficulty one.
--
-- `worth` is a rough multiplier on how much of a fight it is, for a caller
-- composing a sequence. It is a starting guess and belongs in
-- docs/balance-updates.md once anybody has watched a fight.
CreatureTypes.rank = Enum.define("CreatureRanks", {
    { "normal",     id = 0, worth = 1,  means = "an ordinary one" },
    { "elite",      id = 1, worth = 3,  means = "a fight for a group" },
    { "rare_elite", id = 2, worth = 4,  means = "uncommon, and a group fight" },
    { "world_boss", id = 3, worth = 20, means = "a raid" },
    { "rare",       id = 4, worth = 2,  means = "uncommon, but ordinary strength" },
    -- Present in the data for two creatures and meaning nothing. Named so a
    -- lookup returns a word instead of nil, since nil here would read as "we
    -- forgot" rather than "the game did".
    { "unknown",    id = 5, worth = 1,  means = "the game does not say" },
})
-- }}}

-- {{{ CreatureTypes.by_id(enum, id)
-- The member with a given game number.
--
-- Built by scan rather than by an index table because both enums are tiny and a
-- parallel index is a second thing to keep in step with the first.
function CreatureTypes.by_id(enum, id)
    for _, member in ipairs(enum.members) do
        if member.id == id then return member end
    end

    local known = {}
    for _, member in ipairs(enum.members) do
        table.insert(known, string.format("%d=%s", member.id, member.name))
    end

    return nil, string.format(
        "%s has no member numbered %s.\n"
     .. "  The game's numbers are: %s.\n"
     .. "  A number outside that set came out of the database, which means\n"
     .. "  either this enum is behind the core or the row is corrupt. Check the\n"
     .. "  header this file names before assuming the row.",
        enum.name, tostring(id), table.concat(known, ", "))
end
-- }}}

return CreatureTypes
