# 042-camera.lua

Where to put a camera, and how to turn a point in a picture back into a point in
the world.

Pure geometry — no renderer, no world, no deployment. Which is why it exists and
is tested while the thing that would actually draw a frame does not exist at all
(issue 1010).

Coordinates are the game's: X and Y horizontal, Z up, orientation in radians
with 0 along +X. Distances in yards.

## Functions

### `Camera.over_shoulder(subject, target, options) -> camera | nil, why`
The shot a creature takes of a thing it is looking at. `subject` is
`{x, y, z, o, eye_height, name}` where `z` is the ground it stands on; `target`
is `{x, y, z}`. `options` takes `side` (`"left"`/`"right"`), `fov`, `aspect`.

### `Camera.from_above(point, height, viewed_from, options) -> camera | nil, why`
The closer look. Hangs `height` above the point and leans toward the viewer, so
the object is seen from the side the creature is actually on.

### `Camera.project(camera, point) -> u, v, depth | nil, why, depth`
Where a world point lands in the picture. `(0,0)` top-left, `(1,1)` bottom-right.
Returns nil for anything behind the camera — not an error, since half the world
is.

### `Camera.unproject(camera, u, v, depth) -> point | nil, why`
The world point behind a pixel. This is how a creature says *that thing, there*
about a picture and gets a new camera aimed at it.

### `Camera.pose(position, look_at, fov, aspect)` · `Camera.describe(camera)`

## The offsets are the specification, converted

| Axis | Feet | Yards | Direction |
|------|------|-------|-----------|
| back | 1 | 0.3048 | horizontal, reverse of the flat view |
| up | 2 | 0.6096 | vertical, above the **eye** |
| side | 1 | 0.3048 | horizontal, perpendicular |

**Horizontal back, horizontal side, vertical up — a rigid shape.** Only the aim
changes with the object's elevation. Backing along the full 3D view axis instead
would slide the camera upward whenever the creature looked down, and looking at
something on the ground would put the camera directly overhead, which is not a
shot over anybody's shoulder. Keeping the shape fixed is what makes two frames
of the same room comparable.

**Up is from the eye, not the feet**, or the camera ends up inside the head of
anything taller than two feet. `DEFAULT_EYE` is 1.7 and is a poor default on
purpose: this deployment runs mod-grownup, which scales models by level, so
callers that know the creature should say so.

**Which shoulder** defaults to the side away from where the target sits relative
to the creature's facing — object on the right, camera on the left. That is a
guess about how frames will read, written as a named rule so real output can
disagree with it in one place. An object dead ahead is a genuine tie and falls
to `left` every time; falling the same way always is worth more than falling the
prettier way sometimes, because it makes the two frames the same shot.

## Depth is along the view axis, not distance from the camera

`project` returns it and `unproject` expects it. The two differ for anything
off-centre, by more the further out it is. Feeding a straight-line distance to
`unproject` lands the point short and to one side — a bug that looks like the
creature being slightly bad at pointing rather than like arithmetic.

## Four refusals, each naming a different real situation

| Situation | Why it is refused |
|---|---|
| camera on its own target | no direction to face; downstream divides produce NaN quietly |
| aimed at the zenith or nadir | no unambiguous "right", so any roll would do and none is correct |
| creature standing inside the object | usually a target that defaulted to the asker's position |
| unprojecting at zero depth | sky, or a gap in the terrain — no surface there to point at |
