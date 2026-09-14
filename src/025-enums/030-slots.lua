--------------------------------------------------------------------------------
-- 030-slots.lua
--
-- The nineteen equipment slots, as an enum, with the numbers the game uses.
--
-- These are what a tool means by "take the chest piece" or "put this in the
-- offhand". They index `character_inventory.slot` for equipped items, where
-- `bag = 0` and the slot is one of these numbers.
--
-- ============================================================================
-- VERIFIED against the deployment's own source, 2026-09-04.
--
--     source-beta/src/server/game/Entities/Player/Player.h:660-681
--     enum EquipmentSlots -- EQUIPMENT_SLOT_START = 0 .. EQUIPMENT_SLOT_END = 19
--
-- Every number below was read out of that enum, not remembered. Re-check after
-- an upstream update with:
--
--     grep -n -A21 "EQUIPMENT_SLOT_START" \
--       <deployment>/source-beta/src/server/game/Entities/Player/Player.h
--
-- Why it is worth checking rather than trusting: a wrong slot number does not
-- error anywhere. It writes an item into a slot that exists, producing a
-- character wearing their boots on their head, or more likely an item that
-- simply vanishes from the interface. Nothing above this file can detect that,
-- so it is caught here or it is not caught.
-- ============================================================================
--
-- The slot numbers run 0 to 18 with no gaps, so `index` (which the enum
-- constructor makes 1-based) is deliberately NOT the game's number. Read
-- `.slot`, never `.index`.
--------------------------------------------------------------------------------

local here = debug.getinfo(1, "S").source:match("^@(.*/)")
local Load = dofile(here .. "../024-load.lua")
local Enum = Load(here .. "026-enum.lua")

return Enum.define("Slots", {
    { "head",      slot =  0, worn = "on the head"                       },
    { "neck",      slot =  1, worn = "around the neck"                   },
    { "shoulders", slot =  2, worn = "on the shoulders"                  },
    -- The shirt. Named `body` by the core and `shirt` by every player who has
    -- ever spoken about it; the core's name wins here because the number is
    -- the core's, and a name that disagrees with its source is how a wrong
    -- number survives review.
    { "body",      slot =  3, worn = "as a shirt"                        },
    { "chest",     slot =  4, worn = "on the chest"                      },
    { "waist",     slot =  5, worn = "at the waist"                      },
    { "legs",      slot =  6, worn = "on the legs"                       },
    { "feet",      slot =  7, worn = "on the feet"                       },
    { "wrists",    slot =  8, worn = "on the wrists"                     },
    { "hands",     slot =  9, worn = "on the hands"                      },
    { "finger1",   slot = 10, worn = "on a finger"                       },
    { "finger2",   slot = 11, worn = "on the other finger"               },
    { "trinket1",  slot = 12, worn = "carried"                           },
    { "trinket2",  slot = 13, worn = "carried"                           },
    { "back",      slot = 14, worn = "over the back"                     },
    { "mainhand",  slot = 15, worn = "in the main hand"                  },
    { "offhand",   slot = 16, worn = "in the off hand"                   },
    { "ranged",    slot = 17, worn = "slung"                             },
    { "tabard",    slot = 18, worn = "over everything"                   },
})
