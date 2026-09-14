--------------------------------------------------------------------------------
-- 042-camera.lua
--
-- Where to put a camera, and how to turn a point in a picture back into a point
-- in the world.
--
-- Two jobs that look separate and are the same job. Placing a camera over a
-- creature's shoulder aimed at something is how a frame gets taken. Unprojecting
-- a pixel out of that frame is how the NEXT camera gets aimed -- because a
-- creature says "that thing, there" about a picture rather than about
-- coordinates, and something has to turn a place in an image into a place in
-- the world.
--
-- Pure geometry. No renderer, no world, no deployment. Every number in comes
-- from a caller and every number out is arithmetic, which is why this exists
-- and is tested while the thing that would actually draw a frame does not exist
-- at all (issue 1010).
--
-- COORDINATES are the game's: X and Y horizontal, Z up, orientation in radians
-- with 0 along +X and increasing counter-clockwise. Distances are yards.
--------------------------------------------------------------------------------

local Camera = {}

-- {{{ OFFSETS
-- Back one foot, up two, one to the side. A foot is 0.3048 of a yard, and a
-- yard is the world unit, so these are the specification converted and nothing
-- more.
--
-- UP is measured from the character's EYE, not its feet. Measuring from the
-- feet would put the camera inside the head of anything taller than two feet.
--
-- The framing consequence of `back` being this small is worth knowing before
-- looking at output and being surprised: at one foot, a character's shoulders
-- fill a large part of the frame, and it is `up` that clears them. These three
-- numbers are a single shape rather than three independent knobs -- shortening
-- `up` without lengthening `back` produces a picture of somebody's neck.
local OFFSETS = {
    back = 0.3048,   -- one foot, along the reverse of the view axis
    up   = 0.6096,   -- two feet, above the eye
    side = 0.3048,   -- one foot, perpendicular to the view axis
}

-- A rough human eye height, used only when a caller supplies none.
--
-- It is a poor default on purpose-adjacent grounds: this deployment runs
-- mod-grownup, which scales player models by level, so a level 4 and a level 40
-- character have their eyes in different places and neither is this number.
-- Callers that know the creature should say so.
local DEFAULT_EYE = 1.7

local DEFAULT_FOV    = math.rad(70)   -- horizontal, radians
local DEFAULT_ASPECT = 16 / 9

Camera.OFFSETS       = OFFSETS
Camera.DEFAULT_EYE   = DEFAULT_EYE
Camera.DEFAULT_FOV   = DEFAULT_FOV
Camera.DEFAULT_ASPECT = DEFAULT_ASPECT
-- }}}

-- {{{ vector helpers
local function subtract(a, b)
    return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }
end

local function add(a, b)
    return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }
end

local function scale(v, k)
    return { x = v.x * k, y = v.y * k, z = v.z * k }
end

local function dot(a, b)
    return a.x * b.x + a.y * b.y + a.z * b.z
end

local function cross(a, b)
    return {
        x = a.y * b.z - a.z * b.y,
        y = a.z * b.x - a.x * b.z,
        z = a.x * b.y - a.y * b.x,
    }
end

local function length(v)
    return math.sqrt(dot(v, v))
end

local function normalise(v)
    local size = length(v)
    if size == 0 then return nil end
    return scale(v, 1 / size)
end
-- }}}

-- {{{ Camera.pose(position, look_at, fov, aspect)
-- A camera at a place, aimed at a place, with its three axes worked out.
--
-- The axes are stored rather than recomputed because projection and
-- unprojection both need all three, and deriving them twice from the same
-- inputs is two chances to derive them differently.
--
-- Refuses a camera sitting exactly on its own target: there is no direction to
-- face, and every downstream calculation would divide by a zero-length vector
-- and quietly produce not-a-number rather than an error.
function Camera.pose(position, look_at, fov, aspect)
    local forward = normalise(subtract(look_at, position))

    if not forward then
        return nil, string.format(
            "a camera cannot look at the point it is standing on.\n"
         .. "  camera and target are both at %.3f %.3f %.3f\n"
         .. "  To debug: the target was probably resolved to the creature's own\n"
         .. "  position, which happens when an object's coordinates were never\n"
         .. "  filled in and defaulted to whoever was asking.",
            position.x, position.y, position.z)
    end

    -- Right-handed basis against world up. A camera aimed exactly at the zenith
    -- or nadir has no unambiguous "right", so the cross product collapses --
    -- worth refusing rather than tilting arbitrarily, because an arbitrary tilt
    -- makes two frames of the same thing unrelatable.
    local world_up = { x = 0, y = 0, z = 1 }
    local right    = normalise(cross(forward, world_up))

    if not right then
        return nil, string.format(
            "a camera aimed straight up or straight down has no 'right'.\n"
         .. "  forward is %.3f %.3f %.3f, which is parallel to world up.\n"
         .. "  Any roll would do and none is correct, so two frames of the same\n"
         .. "  thing could not be compared. Offset the camera sideways first.",
            forward.x, forward.y, forward.z)
    end

    return {
        position = position,
        look_at  = look_at,
        forward  = forward,
        right    = right,
        up       = cross(right, forward),
        fov      = fov or DEFAULT_FOV,
        aspect   = aspect or DEFAULT_ASPECT,
    }
end
-- }}}

-- {{{ Camera.over_shoulder(subject, target, options)
-- The shot a creature takes of a thing it is looking at.
--
-- Back along the view axis, up above the eye, and one foot to a side -- so the
-- creature's own shoulder is in the near frame and the object is centred beyond
-- it. One picture that says "I am looking at that", which is what makes
-- first-person narration line up with what is being narrated.
--
-- The camera aims at the TARGET, not along the creature's facing. A creature
-- can be looking at something it has not turned toward yet.
--
-- `subject`: { x, y, z, o, eye_height }   z is the ground the creature stands on
-- `target`:  { x, y, z }
-- `options`: { side = "left" | "right" | nil, fov, aspect }
function Camera.over_shoulder(subject, target, options)
    options = options or {}

    local eye_height = subject.eye_height or DEFAULT_EYE
    local eye = { x = subject.x, y = subject.y, z = subject.z + eye_height }

    local view = normalise(subtract(target, eye))

    if not view then
        return nil, string.format(
            "%s is standing inside the thing it is looking at.\n"
         .. "  eye and target are both at %.3f %.3f %.3f\n"
         .. "  There is no direction to look, so there is no shot to take.",
            subject.name or "the creature", eye.x, eye.y, eye.z)
    end

    -- Horizontal right, from the view axis. Taken flat rather than from the
    -- full 3D basis so that looking sharply up or down at something does not
    -- roll the sideways offset out of horizontal -- a camera that banks when
    -- the creature looks at its feet is a camera whose frames cannot be
    -- compared to each other.
    local flat = normalise({ x = view.x, y = view.y, z = 0 })

    if not flat then
        return nil, string.format(
            "%s is looking straight up or straight down, so there is no\n"
         .. "  sideways to offset the camera to. This happens when the target is\n"
         .. "  directly overhead or directly underfoot, which for an object in a\n"
         .. "  room usually means its height is wrong rather than its position.",
            subject.name or "the creature")
    end

    local right = { x = -flat.y, y = flat.x, z = 0 }   -- 90 degrees left of flat

    -- Which side. The proposed rule is the side AWAY from where the target sits
    -- relative to the creature's own facing: if the object is off to its right,
    -- the camera goes left, on the reasoning that a creature turns toward what
    -- it looks at and the far-side camera catches the turn rather than the back
    -- of a turned head.
    --
    -- This is a guess about how frames will read, and it is written as a rule
    -- with a name so that looking at real output can disagree with it in one
    -- place. Callers may override.
    local side = options.side

    if not side then
        local facing  = { x = math.cos(subject.o or 0), y = math.sin(subject.o or 0), z = 0 }
        -- Positive means the target lies to the creature's left.
        --
        -- Exactly zero -- an object dead ahead -- is a genuine tie, and it falls
        -- to "left" because a tie has to fall somewhere and falling the same way
        -- every time is worth more than falling the prettier way sometimes. Two
        -- frames of an object straight in front are then the same shot, which is
        -- what lets them be compared.
        local bearing = facing.x * flat.y - facing.y * flat.x
        side = bearing > 0 and "right" or "left"
    end

    local sideways = scale(right, side == "left" and OFFSETS.side or -OFFSETS.side)

    -- Back along the FLAT view direction, not the full 3D one, for the same
    -- reason `right` is taken flat: the offset is a rigid shape held above and
    -- behind the creature, and it should not change shape with how high or low
    -- the object sits. Backing along the 3D axis would slide the camera upward
    -- whenever the creature looked down -- and looking at something on the
    -- ground would put the camera directly overhead, which is not a shot over
    -- anybody's shoulder.
    --
    -- So: horizontal back, horizontal side, vertical up. Only the AIM changes
    -- with elevation, which is what keeps two frames of the same room
    -- comparable to each other.
    local position = add(add(eye, scale(flat, -OFFSETS.back)),
                         add(sideways, { x = 0, y = 0, z = OFFSETS.up }))

    local camera, why = Camera.pose(position, target, options.fov, options.aspect)
    if not camera then return nil, why end

    camera.side    = side
    camera.subject = subject
    return camera
end
-- }}}

-- {{{ Camera.project(camera, point)
-- Where a world point lands in the picture, as (u, v) with (0,0) top-left and
-- (1,1) bottom-right.
--
-- Returns nil for anything behind the camera. That is not an error -- half the
-- world is behind every camera -- so it comes back as a plain nil with a
-- reason, and callers loop over candidates and skip the ones that are not in
-- shot.
--
-- The third return is DEPTH ALONG THE VIEW AXIS, not distance from the camera.
-- The two differ for anything off-centre, and confusing them is the classic way
-- an unprojection lands slightly to one side of what was pointed at.
function Camera.project(camera, point)
    local offset = subtract(point, camera.position)
    local depth  = dot(offset, camera.forward)

    if depth <= 0 then
        return nil, "behind the camera", depth
    end

    local half = math.tan(camera.fov / 2)

    local across = dot(offset, camera.right) / depth / (half)
    local upward = dot(offset, camera.up)    / depth / (half / camera.aspect)

    return (across + 1) / 2, (1 - upward) / 2, depth
end
-- }}}

-- {{{ Camera.unproject(camera, u, v, depth)
-- The world point behind a pixel. The mechanism that lets a creature say "that
-- thing, there" about a picture and have a new camera aimed at it.
--
-- `depth` comes from the frame's depth buffer, which is why issue 1010 says to
-- keep depth buffers from the very first render: a renderer that discards them
-- has to be rebuilt before any of this works.
--
-- `depth` is along the view axis, matching what `project` returns. Feeding it a
-- straight-line distance instead lands the point short and off to one side, by
-- more the further from centre it was -- a bug that looks like the creature
-- being slightly bad at pointing rather than like arithmetic.
function Camera.unproject(camera, u, v, depth)
    if depth <= 0 then
        return nil, string.format(
            "cannot unproject at depth %.3f.\n"
         .. "  Depth is measured along the view axis and is positive in front of\n"
         .. "  the camera. Zero or negative means the depth buffer held nothing\n"
         .. "  at that pixel -- the sky, or a gap in the terrain -- so there is\n"
         .. "  no surface there to point at.", depth)
    end

    local half   = math.tan(camera.fov / 2)
    local across = (u * 2 - 1) * half * depth
    local upward = (1 - v * 2) * (half / camera.aspect) * depth

    return add(camera.position,
        add(scale(camera.forward, depth),
            add(scale(camera.right, across), scale(camera.up, upward))))
end
-- }}}

-- {{{ Camera.from_above(point, height, viewed_from, options)
-- The closer look: a camera hanging above a thing, aimed down at it.
--
-- `viewed_from` is where the creature is, and it only decides which way the
-- camera leans -- the shot is taken from above and slightly toward the viewer,
-- so the object is seen from the side the creature is on rather than from an
-- arbitrary compass direction. A thing examined from the far side is a thing
-- the creature could not actually have walked around to see.
--
-- Straight down is deliberately avoided: a camera exactly overhead has no
-- unambiguous "right" (see Camera.pose), and a plan view of a barrel is a
-- circle.
function Camera.from_above(point, height, viewed_from, options)
    options = options or {}

    local lean = normalise({ x = viewed_from.x - point.x,
                             y = viewed_from.y - point.y, z = 0 })

    if not lean then
        return nil, string.format(
            "cannot look down at %.3f %.3f from directly on top of it.\n"
         .. "  The viewer and the object share a horizontal position, so there\n"
         .. "  is no side to lean toward and the shot would be a plan view --\n"
         .. "  which for most objects is an unreadable circle.",
            point.x, point.y)
    end

    -- Lean back by a third of the height, so the shot looks down at roughly
    -- seventy degrees rather than ninety. Enough to see the top and enough of
    -- the side to tell what it is.
    local back = (options.lean or (height / 3))

    local position = {
        x = point.x + lean.x * back,
        y = point.y + lean.y * back,
        z = point.z + height,
    }

    return Camera.pose(position, point, options.fov, options.aspect)
end
-- }}}

-- {{{ Camera.describe(camera)
function Camera.describe(camera)
    return string.format(
        "camera at %.2f %.2f %.2f looking at %.2f %.2f %.2f  (%s shoulder, %.0f deg)",
        camera.position.x, camera.position.y, camera.position.z,
        camera.look_at.x, camera.look_at.y, camera.look_at.z,
        camera.side or "no", math.deg(camera.fov))
end
-- }}}

return Camera
