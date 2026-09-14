--------------------------------------------------------------------------------
-- 027-hands.lua
--
-- The four ways of reaching the world, as an enum. This is the column the
-- vocabulary table calls `hands`, and the key the mechanism dispatch table is
-- indexed on.
--
-- Order is not alphabetical and is not arbitrary: it runs from the reach that
-- needs least of the deployment to the reach that needs most, and then `none`,
-- which needs nothing at all.
--------------------------------------------------------------------------------

local here = debug.getinfo(1, "S").source:match("^@(.*/)")
local Load = dofile(here .. "../024-load.lua")
local Enum = Load(here .. "026-enum.lua")

return Enum.define("Hands", {

    { "cold",
      -- `short` is what a fixed-width column prints. The enum owns both
      -- spellings so a table cannot invent an abbreviation the code has
      -- never heard of -- which is exactly what happened once already.
      short   = "cold",
      needs   = "database",
      carries = { "sql", "binds", "database" },
      summary = "A database write over the deployment's own MySQL socket. "
             .. "Works while the worldserver is down, and is the only reach "
             .. "that touches a character who is not logged in.",
      -- The trap this hand carries everywhere: if the character IS logged in,
      -- the server holds their state in memory and flushes it over the row on
      -- its next save. The statement succeeds, the row changes, and the change
      -- evaporates with nothing anywhere reporting an error.
      caution = "A cold write to an online character is silently undone." },

    { "live",
      short   = "live",
      needs   = "worldserver",
      carries = { "command" },
      summary = "One game master command over the SOAP console. Instant, "
             .. "visible to everyone standing there, and reaches only "
             .. "characters actually present in the world.",
      -- Much of the GM vocabulary acts on the caller's current selection, and a
      -- SOAP caller has no selection and cannot acquire one. See
      -- 003-live-hand.lua's addressing table -- that limitation is why the cold
      -- hand has to exist at all.
      caution = "Selection-addressed commands cannot be sent this way." },

    { "resident",
      short   = "res",
      needs   = "worldserver",
      carries = { "script", "script_name" },
      summary = "A Lua script installed into the running worldserver through "
             .. "ALE, which stays there and keeps running on the server's "
             .. "tick after the call has returned.",
      -- The only hand whose effect outlives the call. That is what lets a
      -- guard hold a hill and a creature keep narrating; the other two can only
      -- do a thing once and come back.
      caution = "Its effect outlives the call, so removing it is its own act." },

    { "none",
      short   = "none",
      needs   = "nothing",
      carries = {},
      summary = "No reach at all. Neuron answering about itself -- the "
             .. "catalogue, an explanation of a word. Always available.",
      caution = "" },
})
