# 044-regions.lua

A thing in a picture, and how to point at a named part of it.

Covers this file and `043-adjectives.lua`, the closed set it reduces by.

Nothing here knows what a rock is. It knows which pixels somebody said were one,
and how to find the bottom or the near rim of any such set — which is why a
creature can be sent to the near edge of something nobody has named.

## Functions

### `Regions.of(specification) -> region | nil, why`
`{ name, width, height, pixels, frame }`. Pixels are `{x, y, depth?}`. The
`frame` (camera pose + when) is stored **on the region**, so a pixel can never
be paired with a camera that did not take it.

### `Regions.resolve(region, adjective) -> hit | nil, why`
A hit carries the pixel, its normalised `u`/`v` for the camera, `depth` if
known, the adjective member, and the frame.

### `Regions.world_point(hit) -> point | nil, why`
Unprojects through the hit's own frame.

### `Regions.adjective(text)` · `Regions.describe(hit)`

## The adjectives split by what they cost

| Adjective | Reduction | Depth |
|---|---|---|
| lowest / highest | largest / smallest `v` | no |
| leftmost / rightmost | smallest / largest `u` | no |
| centre | centroid, snapped onto the thing | no |
| closest / furthest | smallest / largest depth | **yes** |
| nearest_edge | smallest depth **among boundary pixels** | **yes** |

Image-space adjectives are a scan and cost nothing. Depth adjectives cost one
vmap raycast per candidate — a few hundred against a BVH the server already
keeps for line of sight. `needs_depth` on the enum lets a caller find out the
cost before asking.

**`lowest` is the largest `v`.** Image coordinates put (0,0) top-left, so down
the picture is `v` increasing. Backwards, a creature reaches for the sky when
asked for the bottom of something — which reads as the creature being strange
rather than as an inverted axis.

## Three geometry decisions

**A frame edge is not a thing's edge.** A pixel pressed against the border of the
picture has a missing neighbour, but what is missing is the *picture*. Counting
it as boundary answers "the near edge of the rock" with the place the frame was
cropped — a confident statement about the photographer. So a thing filling the
view has no edge in shot and says so.

**The near edge is not the near point.** Restricting to the boundary is what
makes it an edge. For a convex rock they are the same pixel; for anything with a
lip or a pit they are not.

**The centre snaps onto the thing.** A crescent's centroid lands in its gap, and
pointing at the gap unprojects onto whatever is behind it.

## Ties break the same way every time

`y` then `x`, always. Lua iterates a hash in whatever order it likes, and a
creature walking toward something must not re-resolve to a different pixel each
turn because of it.

## The enum stays exact; one place is forgiving

`Adjectives.of` refuses anything not letter-for-letter a member — that
strictness is what makes identity comparison mean anything. `Regions.adjective`
folds case and separators, so `"Nearest Edge"`, `"nearest-edge"` and
`"nearest_edge"` are one request. `"near edge"` is not, and is refused with the
list.

## Three states on the way to a place

| Hit has | It is | |
|---|---|---|
| pixel only | a pixel | no camera behind it — a confident answer about nowhere |
| pixel + frame | a **direction** | a ray out of the camera, no distance along it |
| pixel + frame + depth | a **place** | unprojects |
