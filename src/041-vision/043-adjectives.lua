--------------------------------------------------------------------------------
-- 043-adjectives.lua
--
-- The spatial words a creature can use about a thing it can see, as an enum.
--
-- "Go to the nearest edge of the rock" is three parts: a thing, an adjective,
-- and a verb. This file is the closed set the middle part comes from.
--
-- The field that earns this being an enum rather than a list is `needs_depth`.
-- Most spatial adjectives are answered by scanning a mask and cost nothing;
-- three of them need to know how far away each candidate pixel is, and that is
-- a vmap raycast per candidate. A caller can therefore find out what a
-- reduction will cost BEFORE asking for it, which is the difference between a
-- creature that says "the lowest bit" freely and one that says "the near edge"
-- deliberately.
--
-- Defined here rather than in src/025-enums/ because this vocabulary belongs to
-- seeing. The enums in that directory -- hands, kinds, refusals -- are the
-- project's own bones and are imported everywhere; these words mean nothing
-- outside a picture.
--------------------------------------------------------------------------------

local here = debug.getinfo(1, "S").source:match("^@(.*/)")
local Load = dofile(here .. "../024-load.lua")
local Enum = Load(here .. "../025-enums/026-enum.lua")

return Enum.define("Adjectives", {

    -- {{{ image-space, free
    -- A scan of the mask and nothing else. Note that `lowest` is the LARGEST v:
    -- image coordinates put (0,0) at the top left, so down the picture is v
    -- increasing. Getting this backwards produces a creature that reaches for
    -- the sky when asked for the bottom of something, which reads as the
    -- creature being strange rather than as an inverted axis.
    { "lowest",     axis = "v", prefer = "max", needs_depth = false,
      boundary_only = false,
      means = "the bottom of it in the picture" },

    { "highest",    axis = "v", prefer = "min", needs_depth = false,
      boundary_only = false,
      means = "the top of it in the picture" },

    { "leftmost",   axis = "u", prefer = "min", needs_depth = false,
      boundary_only = false,
      means = "its left side from here" },

    { "rightmost",  axis = "u", prefer = "max", needs_depth = false,
      boundary_only = false,
      means = "its right side from here" },

    -- Centroid rather than an extreme, and then snapped back to a pixel the
    -- thing actually occupies -- the average of a crescent's pixels is a point
    -- in the gap, and pointing at the gap means unprojecting onto whatever is
    -- behind it.
    { "centre",     axis = "centroid", prefer = "centroid", needs_depth = false,
      boundary_only = false,
      means = "the middle of it" },
    -- }}}

    -- {{{ depth-requiring, one raycast per candidate
    { "closest",    axis = "depth", prefer = "min", needs_depth = true,
      boundary_only = false,
      means = "the part of it nearest to me" },

    { "furthest",   axis = "depth", prefer = "max", needs_depth = true,
      boundary_only = false,
      means = "the part of it furthest from me" },

    -- The one the whole file was written for. An edge is a pixel with a
    -- neighbour that is not part of the thing; the nearest edge is the closest
    -- of those. Restricting to the boundary is what makes it an EDGE rather
    -- than just the closest point -- for a convex rock those are the same pixel
    -- and for anything with a lip or an overhang they are not.
    { "nearest_edge", axis = "depth", prefer = "min", needs_depth = true,
      boundary_only = true,
      means = "the near rim of it, where it stops" },
    -- }}}
})
