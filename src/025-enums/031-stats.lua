--------------------------------------------------------------------------------
-- 031-stats.lua
--
-- The five primary attributes, as an enum, with the indices the game uses.
--
-- These are what a tool means by "modify strength by N". They index the
-- server's per-character stat array and the `character_stats` table's columns.
--
-- ============================================================================
-- VERIFIED against the deployment's own source, 2026-09-04.
--
--     source-beta/src/server/shared/SharedDefines.h:244-253
--     enum Stats -- STAT_STRENGTH = 0 .. STAT_SPIRIT = 4, MAX_STATS 5
--
-- Read out of that enum, not remembered. Re-check after an upstream update:
--
--     grep -n -A9 "^enum Stats" \
--       <deployment>/source-beta/src/server/shared/SharedDefines.h
--
-- A wrong index adds strength to the intellect column. The character is not
-- broken and nothing errors; they are simply wrong in a way that only shows up
-- as a number on a sheet somebody eventually reads.
-- ============================================================================
--
-- These five are the primary attributes only. Derived numbers -- armour, attack
-- power, resistances, crit -- are computed by the server from these plus gear
-- and are NOT settable. A tool offering "modify armour by N" would be offering
-- something the server recomputes away on the next stat update, which is the
-- silent-overwrite failure again in a different costume.
--------------------------------------------------------------------------------

local here = debug.getinfo(1, "S").source:match("^@(.*/)")
local Load = dofile(here .. "../024-load.lua")
local Enum = Load(here .. "026-enum.lua")

return Enum.define("Stats", {
    { "strength",  stat = 0, column = "strength",
      governs = "melee attack power, and how much a shield blocks" },
    { "agility",   stat = 1, column = "agility",
      governs = "armour, dodge, crit, and ranged attack power" },
    { "stamina",   stat = 2, column = "stamina",
      governs = "health, at ten points of health per point above the first twenty" },
    { "intellect", stat = 3, column = "intellect",
      governs = "mana pool, spell crit, and how fast a weapon skill rises" },
    { "spirit",    stat = 4, column = "spirit",
      governs = "health and mana regenerated while not acting" },
})
