--------------------------------------------------------------------------------
-- 028-kinds.lua
--
-- What running an operation costs. The `k` column of the vocabulary table.
--
-- This enum replaces a boolean named `reversible`, which had two states for
-- three real ones. The third is the dangerous one -- a change that writes a
-- receipt the receipt cannot undo -- and a boolean had no way to say it, so it
-- was said in prose and nothing enforced it.
--
-- Each member says what the declaration must supply and what the dispatcher
-- must do, so `kind` is a switch rather than a label.
--------------------------------------------------------------------------------

local here = debug.getinfo(1, "S").source:match("^@(.*/)")
local Load = dofile(here .. "../024-load.lua")
local Enum = Load(here .. "026-enum.lua")

return Enum.define("Kinds", {

    { "read",
      glyph            = "?",
      declares         = { "run" },
      -- Whether the dispatcher runs it on the spot or plans it and waits.
      --
      -- Was decided by comparing against the name "read", which meant adding a
      -- kind that also runs immediately required finding every such comparison.
      -- A field on the member is the enum doing its job: the member says what
      -- the dispatcher must do.
      runs_now         = true,
      writes_receipt   = false,
      captures_prior   = false,
      needs_confirm    = false,
      summary = "Reads only. No apply, no receipt, no gate. Safe at any "
             .. "moment, and safe to hand a model with nothing in front of it." },

    { "change",
      glyph            = "+",
      declares         = { "plan", "apply" },
      runs_now         = false,
      writes_receipt   = true,
      -- The read before every write is the price of reversibility and it is
      -- paid on every single write. It is what puts enough in the receipt to
      -- build the inverse, which is the only reason character.return exists.
      captures_prior   = true,
      needs_confirm    = false,
      summary = "Changes the world, and the receipt can put it back." },

    { "final",
      glyph            = "!",
      declares         = { "plan", "apply" },
      runs_now         = false,
      writes_receipt   = true,
      -- The receipt is a record, not an undo. It says what was destroyed; it
      -- cannot reconstruct it.
      captures_prior   = false,
      -- Deliberately optional in the schema rather than required. Required
      -- means a model fills it with true on the first attempt and the gate is
      -- decorative; optional means the model must be told no once, out loud,
      -- while somebody is reading.
      needs_confirm    = true,
      summary = "Changes the world, and nothing can put it back." },

    { "internal",
      glyph            = "~",
      declares         = { "run" },
      -- Immediately, like a read, and for the same reason: there is nothing to
      -- agree to. A model shortening its own memory mid-sentence cannot stop
      -- and wait for somebody to approve it -- the whole point is that it
      -- happens while the model is still working.
      runs_now         = true,
      -- No receipt, because a receipt is a record of something done to the
      -- WORLD, and this is not. It changes what one conversation carries
      -- forward and nothing outside it. The transcript is its record.
      writes_receipt   = false,
      captures_prior   = false,
      needs_confirm    = false,
      summary = "Changes nothing outside the conversation it is spoken in. "
             .. "No receipt, no gate -- the transcript is the record." },
})
