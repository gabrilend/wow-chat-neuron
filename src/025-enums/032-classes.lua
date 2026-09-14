--------------------------------------------------------------------------------
-- 032-classes.lua
--
-- The nine playable classes of 3.3.5a, as an enum.
--
-- The class ids are verified: they are the same values 005-world-read.lua has
-- been reading out of the `characters` table for twenty-five thousand real
-- rows. Note that id 10 does not exist -- the gap is the game's, not an
-- omission, and `index` is therefore NOT the class id. Read `.id`.
--
-- The colours are the ones every WoW player already reads without thinking,
-- which makes them the cheapest meaning available: a list of names becomes a
-- list of roles at a glance.
--
-- DUPLICATION, KNOWN: assets/chat.html carries these same ten hex values as CSS
-- custom properties, because a served static page cannot read a Lua module. If
-- one changes, both change. The eventual fix is for the page to fetch its
-- palette from here rather than declare it; until then this comment is the
-- link between the two homes.
--------------------------------------------------------------------------------

local here = debug.getinfo(1, "S").source:match("^@(.*/)")
local Load = dofile(here .. "../024-load.lua")
local Enum = Load(here .. "026-enum.lua")

return Enum.define("Classes", {
    { "warrior",       id =  1, label = "Warrior",       colour = "#c79c6e",
      resource = "rage"   },
    { "paladin",       id =  2, label = "Paladin",       colour = "#f58cba",
      resource = "mana"   },
    { "hunter",        id =  3, label = "Hunter",        colour = "#abd473",
      resource = "mana"   },
    { "rogue",         id =  4, label = "Rogue",         colour = "#fff569",
      resource = "energy" },
    { "priest",        id =  5, label = "Priest",        colour = "#ffffff",
      resource = "mana"   },
    { "death_knight",  id =  6, label = "Death Knight",  colour = "#c41f3b",
      resource = "runic"  },
    { "shaman",        id =  7, label = "Shaman",        colour = "#0070de",
      resource = "mana"   },
    { "mage",          id =  8, label = "Mage",          colour = "#69ccf0",
      resource = "mana"   },
    { "warlock",       id =  9, label = "Warlock",       colour = "#9482c9",
      resource = "mana"   },
    -- id 10 is not a class. The gap is real.
    { "druid",         id = 11, label = "Druid",         colour = "#ff7d0a",
      resource = "mana"   },
})
