--------------------------------------------------------------------------------
-- tests/042-camera.test.lua
--
-- Camera placement and the projection round trip.
--
-- The round trip is the one that matters. Unprojection is how a creature aims a
-- new camera at something it pointed to in an old picture, and a round trip
-- that is slightly wrong does not look like arithmetic when it fails -- it
-- looks like a creature that is a bit bad at pointing, examines the wrong
-- thing, and narrates about it confidently.
--------------------------------------------------------------------------------

local NEURON = "/mnt/mtwo/games/azeroth-core/wow-chat-neuron"

local Load   = dofile(NEURON .. "/src/024-load.lua")
local Camera = Load(NEURON .. "/src/041-vision/042-camera.lua")

local passed, failed = 0, 0

-- {{{ check / close / near_point
local function check(label, got, want)
    if got == want then passed = passed + 1 else
        failed = failed + 1
        print(string.format("FAIL  %s\n        got  %s\n        want %s",
            label, tostring(got), tostring(want)))
    end
end

local function close(label, got, want, tolerance)
    if got and math.abs(got - want) <= (tolerance or 0.0001) then
        passed = passed + 1
    else
        failed = failed + 1
        print(string.format("FAIL  %s\n        got  %s\n        want %s",
            label, tostring(got), tostring(want)))
    end
end

local function near_point(label, got, want, tolerance)
    tolerance = tolerance or 0.0001
    if got and math.abs(got.x - want.x) <= tolerance
           and math.abs(got.y - want.y) <= tolerance
           and math.abs(got.z - want.z) <= tolerance then
        passed = passed + 1
    else
        failed = failed + 1
        print(string.format("FAIL  %s\n        got  %s\n        want %.4f %.4f %.4f",
            label,
            got and string.format("%.4f %.4f %.4f", got.x, got.y, got.z) or "nil",
            want.x, want.y, want.z))
    end
end
-- }}}

-- A creature at the origin facing +X, eyes at 1.7 yards. An object ten yards
-- ahead at chest height.
local WALKER = { x = 0, y = 0, z = 0, o = 0, eye_height = 1.7, name = "the walker" }
local AHEAD  = { x = 10, y = 0, z = 1.2 }

-- {{{ the offsets are the specification, converted
close("back is one foot in yards",   Camera.OFFSETS.back, 0.3048)
close("up is two feet in yards",     Camera.OFFSETS.up,   0.6096)
close("side is one foot in yards",   Camera.OFFSETS.side, 0.3048)
-- }}}

-- {{{ over the shoulder
local shot = Camera.over_shoulder(WALKER, AHEAD)

check("a shot is taken",  shot ~= nil, true)

-- Behind the creature: further from the object than the eye is.
local eye = { x = 0, y = 0, z = 1.7 }
local function flat_range(a, b)
    return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2)
end
check("the camera is behind the eye",
    flat_range(shot.position, AHEAD) > flat_range(eye, AHEAD),               true)

-- Up is measured from the EYE, not the feet. A camera 0.61 above the ground
-- would be at the creature's knees.
-- Exactly two feet, whatever the object's elevation: the offset is a rigid
-- shape and only the aim changes. Backing along the 3D view axis instead would
-- slide the camera upward whenever the creature looked down.
close("the camera is two feet above the eye",
    shot.position.z, 1.7 + Camera.OFFSETS.up, 0.0001)

local at_its_feet = Camera.over_shoulder(WALKER, { x = 2, y = 0, z = 0 })
close("and still two feet above when looking down",
    at_its_feet.position.z, 1.7 + Camera.OFFSETS.up, 0.0001)

-- And to a side, so the shoulder is not centred in frame.
check("the camera is offset sideways", math.abs(shot.position.y) > 0.3,      true)

-- It aims at the object, not along the creature's facing.
near_point("the camera aims at the object",  shot.look_at, AHEAD)
-- }}}

-- {{{ which shoulder
-- Proposed rule: the side away from where the target sits relative to facing.
local to_the_left  = Camera.over_shoulder(WALKER, { x = 5, y =  5, z = 1.2 })
local to_the_right = Camera.over_shoulder(WALKER, { x = 5, y = -5, z = 1.2 })

check("an object on the left gets the right shoulder", to_the_left.side,  "right")
check("an object on the right gets the left shoulder", to_the_right.side, "left")

-- An object dead ahead is a tie, and a tie has to fall somewhere. Falling the
-- same way every time is what lets two frames of it be compared.
check("dead ahead is a deterministic tie",  shot.side,                      "left")
check("and ties the same way twice",
    Camera.over_shoulder(WALKER, AHEAD).side,                               "left")

-- And a caller may say otherwise.
local forced = Camera.over_shoulder(WALKER, AHEAD, { side = "right" })
check("a caller can override the side",   forced.side,                     "right")
check("and it goes the other way",
    (forced.position.y > 0) ~= (shot.position.y > 0),                       true)
-- }}}

-- {{{ the round trip -- the one that matters
-- Point at something in a picture, get the world position back.
for _, target in ipairs({
    { x = 10, y =  0,  z = 1.2 },     -- dead centre
    { x = 10, y =  3,  z = 1.2 },     -- off to one side
    { x = 10, y = -2,  z = 4.0 },     -- high and to the other
    { x =  4, y =  1,  z = 0.1 },     -- close and low
    { x = 40, y = -9,  z = 8.0 },     -- far and off-axis
}) do
    local frame = Camera.over_shoulder(WALKER, AHEAD)
    local u, v, depth = Camera.project(frame, target)

    if u then
        near_point(string.format("round trip through the picture at %.0f,%.0f,%.1f",
            target.x, target.y, target.z),
            Camera.unproject(frame, u, v, depth), target, 0.0005)
    else
        check(string.format("point at %.0f,%.0f is in shot", target.x, target.y),
            true, false)
    end
end
-- }}}

-- {{{ what a picture holds and what it does not
local frame = Camera.over_shoulder(WALKER, AHEAD)

local u, v = Camera.project(frame, AHEAD)
close("the aimed-at object is centred across", u, 0.5, 0.02)
close("and centred up and down",               v, 0.5, 0.02)

-- Half the world is behind every camera. Not an error.
local behind, why = Camera.project(frame, { x = -20, y = 0, z = 1.2 })
check("something behind the camera is not in shot", behind,                 nil)
check("and says so plainly",                        why,      "behind the camera")

-- A pixel with nothing behind it -- sky, or a hole in the terrain.
local nothing, sky_why = Camera.unproject(frame, 0.5, 0.1, 0)
check("a pixel with no surface is refused",  nothing,                       nil)
check("and explains what zero depth means",
    sky_why:find("no surface there", 1, true) ~= nil,                       true)
-- }}}

-- {{{ depth is along the view axis, not distance from the camera
-- The two differ for anything off-centre. Confusing them lands an unprojection
-- short and to one side, by more the further from centre it was.
local off_axis = { x = 10, y = 6, z = 1.2 }
local _, _, depth = Camera.project(frame, off_axis)
local straight_line = math.sqrt(
    (off_axis.x - frame.position.x)^2 +
    (off_axis.y - frame.position.y)^2 +
    (off_axis.z - frame.position.z)^2)

check("depth and distance genuinely differ off-axis",
    math.abs(straight_line - depth) > 1.0,                                  true)
-- }}}

-- {{{ the closer look, from above
local closer = Camera.from_above({ x = 10, y = 0, z = 1.2 }, 3, WALKER)

check("a look from above is taken",  closer ~= nil,                         true)
close("it hangs the asked-for height above",  closer.position.z, 4.2, 0.0001)
check("it leans toward the viewer rather than straight down",
    closer.position.x < 10,                                                 true)
check("and is not a plan view",
    math.abs(closer.forward.z) < 0.99,                                      true)
-- }}}

-- {{{ refusals
local nowhere, standing_in_it = Camera.over_shoulder(WALKER, { x = 0, y = 0, z = 1.7 })
check("standing inside the object is refused",  nowhere,                    nil)
check("and names the creature",
    standing_in_it:find("the walker", 1, true) ~= nil,                      true)

local overhead, no_side = Camera.over_shoulder(WALKER, { x = 0, y = 0, z = 20 })
check("straight overhead is refused",  overhead,                            nil)
check("and says why there is no sideways",
    no_side:find("straight up", 1, true) ~= nil,                            true)

local on_top, no_lean = Camera.from_above({ x = 0, y = 0, z = 0 }, 3, WALKER)
check("looking down from directly on top is refused",  on_top,              nil)
check("and says it would be a plan view",
    no_lean:find("plan view", 1, true) ~= nil,                              true)
-- }}}

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
