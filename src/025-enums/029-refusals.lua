--------------------------------------------------------------------------------
-- 028-refusals.lua
--
-- The four kinds of failure, as an enum.
--
-- Failures are values here, not exceptions, and the set is kept this small on
-- purpose: the asking loop turns any of them into a tool result with useful
-- text, and a caller -- person or model -- can be told what to do next from the
-- kind alone. Four is enough to say something useful and few enough that every
-- one of them can be handled.
--
-- Until now this set existed only as a table in
-- docs/datapath-operation-dispatch.md, which no code read.
--------------------------------------------------------------------------------

local here = debug.getinfo(1, "S").source:match("^@(.*/)")
local Load = dofile(here .. "../024-load.lua")
local Enum = Load(here .. "026-enum.lua")

return Enum.define("Refusals", {

    { "unknown",
      means  = "No such operation, roster, place, item list, or receipt.",
      -- The message is the only thing telling a model what DOES exist, which is
      -- why near matches are part of the refusal rather than a nicety.
      remedy = "Use a different name. The message lists near matches.",
      retry  = false },

    { "argument",
      means  = "An argument was the wrong type, or out of range.",
      remedy = "Fix the named argument. The message says what was wanted.",
      retry  = false },

    { "unavailable",
      means  = "Every hand this operation could use is down.",
      -- The only one of the four where doing nothing and trying later is a real
      -- answer, which is why it is the only one with retry set.
      remedy = "Start the service the message names, or wait.",
      retry  = true },

    { "refused",
      means  = "The operation could run, and must not.",
      -- Usually a character is online and a cold write would be silently
      -- overwritten. This is the guard doing its job, not a malfunction.
      remedy = "Read why. Usually somebody logged in between plan and apply.",
      retry  = false },
})
