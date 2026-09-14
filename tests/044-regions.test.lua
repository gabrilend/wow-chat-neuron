--------------------------------------------------------------------------------
-- tests/044-regions.test.lua
--
-- "Go to the nearest edge of the rock", without a rock, a camera, or a world.
--
-- The shapes below are drawn as text and turned into pixel masks, because the
-- questions here are all about geometry that has to be READ to be checked. A
-- crescent whose centre lands in the gap, a slab that fills the frame and so
-- has no visible edge, a near rim that is not the same pixel as the near point
-- -- these are each one picture and several paragraphs.
--------------------------------------------------------------------------------

local NEURON = "/mnt/mtwo/games/azeroth-core/wow-chat-neuron"

local Load    = dofile(NEURON .. "/src/024-load.lua")
local Regions = Load(NEURON .. "/src/041-vision/044-regions.lua")
local Camera  = Load(NEURON .. "/src/041-vision/042-camera.lua")

local passed, failed = 0, 0

-- {{{ check
local function check(label, got, want)
    if got == want then passed = passed + 1 else
        failed = failed + 1
        print(string.format("FAIL  %s\n        got  %s\n        want %s",
            label, tostring(got), tostring(want)))
    end
end
-- }}}

-- {{{ mask(name, rows, depth_of)
-- Turn a drawing into a region. '#' is part of the thing, '.' is not.
-- `depth_of(x, y)` supplies depth, or nil for a region with none.
local function mask(name, rows, depth_of, frame)
    local pixels = {}
    for y = 1, #rows do
        for x = 1, #rows[y] do
            if rows[y]:sub(x, x) == "#" then
                table.insert(pixels, { x = x - 1, y = y - 1,
                    depth = depth_of and depth_of(x - 1, y - 1) or nil })
            end
        end
    end
    return (Regions.of {
        name = name, width = #rows[1], height = #rows,
        pixels = pixels, frame = frame,
    })
end
-- }}}

-- A rock in the middle of a ten by six frame. Depth falls off toward the top of
-- the picture, so the bottom of it is also the near side -- which is what a
-- rock on the ground in front of you actually looks like.
local ROCK_ROWS = {
    "..........",
    "...####...",
    "..######..",
    "..######..",
    "...####...",
    "..........",
}
local function sloping_depth(_, y) return 12 - y end
local ROCK = mask("the rock", ROCK_ROWS, sloping_depth)

-- {{{ the image-space adjectives cost nothing and read off the picture
local lowest = Regions.resolve(ROCK, "lowest")
check("lowest is the bottom row of the shape",   lowest.y,                  4)

local highest = Regions.resolve(ROCK, "highest")
check("highest is the top row",                  highest.y,                 1)

local leftmost = Regions.resolve(ROCK, "leftmost")
check("leftmost is the left column",             leftmost.x,                2)

local rightmost = Regions.resolve(ROCK, "rightmost")
check("rightmost is the right column",           rightmost.x,               7)

-- Down the picture is v INCREASING, so `lowest` is the largest y. Getting this
-- backwards makes a creature reach for the sky when asked for the bottom.
check("lowest is below highest in the picture",  lowest.v > highest.v,      true)
-- }}}

-- {{{ pixel centres, not corners
-- Half a pixel is invisible in a picture and a real offset forty yards out.
check("u is the pixel centre",  leftmost.u,             (2 + 0.5) / 10)
check("v is the pixel centre",  highest.v,              (1 + 0.5) / 6)
-- }}}

-- {{{ depth adjectives
local closest = Regions.resolve(ROCK, "closest")
check("closest is the nearest depth",   closest.depth,   8)
check("which here is the bottom row",   closest.y,       4)

local furthest = Regions.resolve(ROCK, "furthest")
check("furthest is the far depth",      furthest.depth,  11)
-- }}}

-- {{{ the near edge is not the near point
-- A shape with a lip: the nearest pixel overall sits in the interior, so
-- `closest` and `nearest_edge` must disagree. If they never disagreed, the
-- boundary restriction would be doing nothing.
local LIPPED = {
    "..........",
    "..######..",
    "..######..",
    "..######..",
    "..######..",
    "..........",
}
-- One interior pixel is much nearer than anything on the rim.
local function pitted(x, y)
    if x == 4 and y == 2 then return 1 end
    return 10
end
local lip = mask("the lipped rock", LIPPED, pitted)

check("closest finds the interior pit",
    Regions.resolve(lip, "closest").x, 4)
check("and it is genuinely inside",
    Regions.resolve(lip, "closest").y, 2)

local rim = Regions.resolve(lip, "nearest edge")
check("nearest edge stays on the rim",  rim.depth,                          10)
check("and is not the pit",             rim.x == 4 and rim.y == 2,          false)

-- The spelling a person or a model would actually write.
check("spaces are forgiven",   Regions.resolve(lip, "nearest edge").x,  rim.x)
check("hyphens are forgiven",  Regions.resolve(lip, "nearest-edge").x,  rim.x)
check("capitals are forgiven", Regions.resolve(lip, "Nearest Edge").x,  rim.x)
-- }}}

-- {{{ centre snaps onto the thing
-- A crescent's average lands in its gap. Pointing there unprojects onto
-- whatever is behind it, so the answer must be a pixel the thing occupies.
local CRESCENT = {
    "..####....",
    ".##..##...",
    ".##...##..",
    ".##..##...",
    "..####....",
}
local moon = mask("the crescent", CRESCENT)
local middle = Regions.resolve(moon, "centre")

local occupied = moon.grid[middle.y * moon.width + middle.x] ~= nil
check("the centre is a pixel the thing occupies",  occupied,                true)
-- }}}

-- {{{ something filling the frame has no edge in shot
local SLAB = { "####", "####", "####" }
local wall = mask("the wall", SLAB, function() return 5 end)

local no_edge, edge_why = Regions.resolve(wall, "nearest edge")
check("a thing filling the picture has no visible edge",  no_edge,          nil)
check("and says the picture was cropped, not the thing",
    edge_why:find("outside what the camera saw", 1, true) ~= nil,           true)

-- Adjectives that need no edge still answer.
check("but 'closest' still works on it",
    Regions.resolve(wall, "closest").depth,                                 5)
-- }}}

-- {{{ refusals
local depthless = mask("the shape", ROCK_ROWS)

local no_depth, depth_why = Regions.resolve(depthless, "closest")
check("a depth adjective on a depthless region is refused",  no_depth,      nil)
check("and counts how much is missing",
    depth_why:find("20 of its 20 pixels", 1, true) ~= nil,                  true)
check("and points at the free adjectives",
    depth_why:find("'lowest' and 'leftmost'", 1, true) ~= nil,              true)

check("but image-space adjectives answer anyway",
    Regions.resolve(depthless, "lowest").y,                                 4)

local unknown, unknown_why = Regions.resolve(ROCK, "beside")
check("an unknown adjective is refused",   unknown,                         nil)
check("and lists the real ones",
    unknown_why:find("lowest, highest", 1, true) ~= nil,                    true)

local empty, empty_why = Regions.of { name = "the ghost", width = 4, height = 4,
                                      pixels = {} }
check("a region with no pixels is refused",  empty,                         nil)
check("and does not claim it is at the origin",
    empty_why:find("cannot see it", 1, true) ~= nil,                        true)

local sizeless = Regions.of { name = "x", pixels = { { x = 1, y = 1 } } }
check("a region with no frame size is refused",  sizeless,                  nil)
-- }}}

-- {{{ the same question twice gives the same pixel
-- Lua iterates a hash in whatever order it likes. A creature walking toward
-- something must not re-resolve to a different pixel each turn because of it.
local first, same = Regions.resolve(ROCK, "lowest"), true
for _ = 1, 20 do
    local again = Regions.resolve(mask("the rock", ROCK_ROWS, sloping_depth), "lowest")
    if again.x ~= first.x or again.y ~= first.y then same = false end
end
check("resolution is deterministic across rebuilds",  same,                 true)
-- }}}

-- {{{ pixel to place
local WALKER = { x = 0, y = 0, z = 0, o = 0, eye_height = 1.7 }
local shot   = Camera.over_shoulder(WALKER, { x = 10, y = 0, z = 1.2 })
local seen   = mask("the rock", ROCK_ROWS, sloping_depth, { camera = shot })

local hit   = Regions.resolve(seen, "nearest edge")
local place = Regions.world_point(hit)

check("a pixel becomes a place",   place ~= nil,                            true)

-- And the place is where that pixel was looking: project it back.
local back_u, back_v = Camera.project(shot, place)
check("and the place lands back on its own pixel",
    math.abs(back_u - hit.u) < 0.0001 and math.abs(back_v - hit.v) < 0.0001, true)

-- A pixel with no camera behind it is a confident answer about nowhere.
local orphan = Regions.resolve(ROCK, "lowest")
local nowhere, orphan_why = Regions.world_point(orphan)
check("a pixel with no frame cannot become a place",  nowhere,              nil)
check("and says the direction is unknown",
    orphan_why:find("points is unknown", 1, true) ~= nil,      true)

-- A pixel with a camera but no depth is a direction, not a place.
local aimless = Regions.resolve(
    mask("the rock", ROCK_ROWS, nil, { camera = shot }), "lowest")
local _, aimless_why = Regions.world_point(aimless)
check("without depth it is a direction, not a place",
    aimless_why:find("a direction and not a place", 1, true) ~= nil,        true)
-- }}}

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
