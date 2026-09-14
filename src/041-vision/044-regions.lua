--------------------------------------------------------------------------------
-- 044-regions.lua
--
-- A thing in a picture, and how to point at a named part of it.
--
-- "The nearest edge of the rock" is a region and an adjective. The region is
-- whatever the vision pass decided was the rock -- a set of pixels, nothing
-- more. The adjective is a reduction over that set. The answer is one pixel,
-- which unprojects to a place in the world, which is somewhere a creature can
-- be told to walk.
--
-- Nothing here knows what a rock is. It knows which pixels somebody said were
-- one, and how to find the bottom or the near rim of any such set. That is the
-- whole of the abstraction and it is why a creature can be sent to the near
-- edge of something nobody has named.
--
-- Pure. A region is data and a reduction is arithmetic; the camera is only
-- needed for the last step, and only if a caller wants a world point.
--------------------------------------------------------------------------------

local here = debug.getinfo(1, "S").source:match("^@(.*/)")
local Load = dofile(here .. "../024-load.lua")

local Adjectives = Load(here .. "043-adjectives.lua")
local Camera     = Load(here .. "042-camera.lua")

local Regions = {}

Regions.Adjectives = Adjectives

-- {{{ Regions.adjective(text)
-- Text to member, forgiving the shapes a person or a model actually writes.
--
-- The enum itself stays exact -- `Adjectives.of` refuses anything that is not
-- letter-for-letter a member, and that strictness is what makes identity
-- comparison mean something. So the forgiveness lives here, in one named place,
-- and consists only of case and of the separators between words. "Nearest Edge"
-- and "nearest-edge" and "nearest edge" are all the same request; "near edge"
-- is not, and is refused with the list.
function Regions.adjective(text)
    if type(text) ~= "string" then
        return Adjectives.of(text)   -- let the enum produce the type complaint
    end

    return Adjectives.of((text:lower():gsub("[%s%-]+", "_")))
end
-- }}}

-- {{{ Regions.of(specification)
-- Build a region from the pixels a vision pass claimed.
--
--   name    what the thing was recognised as, for messages
--   width   the frame's width in pixels
--   height  the frame's height
--   pixels  { { x = , y = , depth = (optional) }, ... }
--   frame   the camera pose the picture was taken from, and when
--
-- `frame` is stored on the region rather than passed to resolve, so that a
-- pixel can never be paired with a camera it did not come from. A resolution
-- computed against a stale pose puts the point somewhere the creature never
-- looked, and nothing downstream could tell.
function Regions.of(specification)
    local pixels = specification.pixels or {}
    local width  = specification.width
    local height = specification.height

    if not width or not height or width <= 0 or height <= 0 then
        return nil, string.format(
            "a region needs the size of the frame it was found in.\n"
         .. "  got width=%s height=%s\n"
         .. "  Without it a pixel cannot be turned into the normalised position\n"
         .. "  the camera works in, so the region can be scanned and never\n"
         .. "  pointed at.", tostring(width), tostring(height))
    end

    -- Keyed grid rather than a list, because finding whether a neighbour is part
    -- of the thing is the inner loop of edge detection and must be one lookup.
    local grid, count, without_depth = {}, 0, 0

    for _, pixel in ipairs(pixels) do
        local key = pixel.y * width + pixel.x
        if grid[key] == nil then
            grid[key] = { x = pixel.x, y = pixel.y, depth = pixel.depth }
            count = count + 1
            if pixel.depth == nil then without_depth = without_depth + 1 end
        end
    end

    if count == 0 then
        return nil, string.format(
            "the region called '%s' has no pixels in it.\n"
         .. "  An empty region is a thing the vision pass named and then did not\n"
         .. "  locate. Nothing can be pointed at, and the honest answer upward is\n"
         .. "  that the creature cannot see it -- not that it is at the origin.",
            specification.name or "something")
    end

    return {
        name          = specification.name or "something",
        width         = width,
        height        = height,
        frame         = specification.frame,
        grid          = grid,
        count         = count,
        without_depth = without_depth,
    }
end
-- }}}

-- {{{ boundary_of(region)
-- The pixels where the thing stops.
--
-- A pixel is on the boundary when one of its four neighbours is inside the
-- frame and is NOT part of the thing.
--
-- The "inside the frame" clause is the subtle half. A pixel pressed against the
-- edge of the picture has a missing neighbour, but what is missing there is the
-- PICTURE, not the thing -- the rock carries on and the camera stopped. Counting
-- it as an edge would answer "the near edge of the rock" with a point that is
-- simply where the frame was cropped, which is a confident answer about the
-- photographer rather than about the rock.
local function boundary_of(region)
    local edge, width = {}, region.width

    for _, pixel in pairs(region.grid) do
        local touching_frame =
            pixel.x == 0 or pixel.y == 0
            or pixel.x == width - 1 or pixel.y == region.height - 1

        if not touching_frame then
            local exposed =
                   region.grid[ pixel.y      * width + pixel.x - 1] == nil
                or region.grid[ pixel.y      * width + pixel.x + 1] == nil
                or region.grid[(pixel.y - 1) * width + pixel.x    ] == nil
                or region.grid[(pixel.y + 1) * width + pixel.x    ] == nil

            if exposed then table.insert(edge, pixel) end
        end
    end

    return edge
end
-- }}}

-- {{{ candidates_of(region, adjective)
local function candidates_of(region, adjective)
    if not adjective.boundary_only then
        local all = {}
        for _, pixel in pairs(region.grid) do table.insert(all, pixel) end
        return all
    end

    local edge = boundary_of(region)

    if #edge == 0 then
        return nil, string.format(
            "'%s' fills the whole picture, so none of its edges are in shot.\n"
         .. "  Every pixel of it is pressed against the frame, which means where\n"
         .. "  it stops is outside what the camera saw. Answering anyway would\n"
         .. "  point at where the picture was cropped rather than at the thing.\n"
         .. "  To debug: step back and take the frame again, or ask for a part\n"
         .. "  that does not need an edge -- 'closest' and 'lowest' both work on\n"
         .. "  something filling the view.", region.name)
    end

    return edge
end
-- }}}

-- {{{ better(candidate, best, adjective)
-- Is this pixel a better answer than the one we have?
--
-- Ties break on y then x, always, so two resolutions of the same region give
-- the same pixel. A creature walking toward something must not re-resolve to a
-- different pixel each turn merely because a table iterated in a different
-- order, which in Lua it will.
local function better(candidate, best, adjective)
    local axis = adjective.axis
    local a = axis == "depth" and candidate.depth
           or axis == "u"     and candidate.x
           or                     candidate.y
    local b = axis == "depth" and best.depth
           or axis == "u"     and best.x
           or                     best.y

    if a ~= b then
        if adjective.prefer == "min" then return a < b end
        return a > b
    end

    if candidate.y ~= best.y then return candidate.y < best.y end
    return candidate.x < best.x
end
-- }}}

-- {{{ centre_of(candidates)
-- The centroid, snapped back to a pixel the thing actually occupies.
--
-- The average of a crescent's pixels lands in the gap. Pointing there would
-- unproject onto whatever is behind the thing, so the answer is the occupied
-- pixel nearest that average -- which is on the thing, always, by construction.
local function centre_of(candidates)
    local sum_x, sum_y = 0, 0
    for _, pixel in ipairs(candidates) do
        sum_x, sum_y = sum_x + pixel.x, sum_y + pixel.y
    end

    local mid_x, mid_y = sum_x / #candidates, sum_y / #candidates
    local best, best_range

    for _, pixel in ipairs(candidates) do
        local range = (pixel.x - mid_x)^2 + (pixel.y - mid_y)^2

        if not best or range < best_range
        or (range == best_range and (pixel.y < best.y
            or (pixel.y == best.y and pixel.x < best.x))) then
            best, best_range = pixel, range
        end
    end

    return best
end
-- }}}

-- {{{ Regions.resolve(region, adjective_text)
-- Point at the named part of the thing.
--
-- Returns a hit: the pixel, its normalised position for the camera, its depth
-- if known, the adjective that chose it, and the frame it came from.
function Regions.resolve(region, adjective_text)
    local adjective, why = Regions.adjective(adjective_text)
    if not adjective then return nil, why end

    -- Depth is checked before the scan rather than during it, so the message can
    -- say how much of the thing is missing depth instead of failing on whichever
    -- pixel happened to be reached first.
    if adjective.needs_depth and region.without_depth > 0 then
        return nil, string.format(
            "cannot find the %s of '%s': %d of its %d pixels have no depth.\n"
         .. "  Depth comes from a raycast against the server's collision data,\n"
         .. "  one ray per candidate pixel, and it is only fetched when an\n"
         .. "  adjective needs it. This one does.\n"
         .. "  To debug: was depth requested for this region at all? Adjectives\n"
         .. "  like 'lowest' and 'leftmost' need none and would answer now.",
            adjective.name, region.name, region.without_depth, region.count)
    end

    local candidates, edge_why = candidates_of(region, adjective)
    if not candidates then return nil, edge_why end

    local chosen

    if adjective.prefer == "centroid" then
        chosen = centre_of(candidates)
    else
        chosen = candidates[1]
        for index = 2, #candidates do
            if better(candidates[index], chosen, adjective) then
                chosen = candidates[index]
            end
        end
    end

    return {
        name      = region.name,
        adjective = adjective,
        x         = chosen.x,
        y         = chosen.y,
        -- Pixel centres, not corners. Off by half a pixel is invisible in a
        -- picture and is a real offset once unprojected forty yards away.
        u         = (chosen.x + 0.5) / region.width,
        v         = (chosen.y + 0.5) / region.height,
        depth     = chosen.depth,
        frame     = region.frame,
        of        = region.count,
        among     = #candidates,
    }
end
-- }}}

-- {{{ Regions.world_point(hit)
-- The place in the world that pixel is looking at.
--
-- The camera comes off the hit's own frame rather than from an argument,
-- because a pixel and a camera that did not take it produce a confident answer
-- about nowhere.
function Regions.world_point(hit)
    if not hit.frame or not hit.frame.camera then
        return nil, string.format(
            "the %s of '%s' is a pixel with no camera behind it.\n"
         .. "  A region carries the frame it was found in so that a pixel can\n"
         .. "  never be paired with a pose that did not take it. This one was\n"
         .. "  built without a frame, so the pixel is real and the direction it\n"
         .. "  points is unknown.", hit.adjective.name, hit.name)
    end

    if not hit.depth then
        return nil, string.format(
            "the %s of '%s' has no depth, so it is a direction and not a place.\n"
         .. "  Every pixel names a ray out of the camera. It takes a distance\n"
         .. "  along that ray to become a point, and that comes from a raycast\n"
         .. "  against the server's collision data.",
            hit.adjective.name, hit.name)
    end

    return Camera.unproject(hit.frame.camera, hit.u, hit.v, hit.depth)
end
-- }}}

-- {{{ Regions.describe(hit)
function Regions.describe(hit)
    return string.format("the %s of %s: pixel %d,%d (%s of %d)%s",
        hit.adjective.name, hit.name, hit.x, hit.y,
        hit.adjective.boundary_only and (hit.among .. " on the edge")
                                     or (hit.among .. " candidates"),
        hit.of,
        hit.depth and string.format(", %.2f yards out", hit.depth) or "")
end
-- }}}

return Regions
