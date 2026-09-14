# 1011 — Going Somewhere You Pointed At

## Status
- Phase: 10 (Narration)
- Blocked by: 1009 (seeing instead of querying), 1010 (the camera pool)
- Blocks: 1006 (NPC tools — `walk to` is one of these)

## Current Behavior

A creature can be moved to a place from the place book, or to coordinates. Both
are the operator's vocabulary: a name somebody wrote down, or six numbers.

Neither is how somebody standing in a room says where they are going. *The near
edge of that rock* is not a name and is not coordinates. It is a thing, and a
side of it, and it means nothing at all until you can see the rock.

## Intended Behavior

**Go to the nearest edge of the rock.**

The rock is a region of pixels in a picture that is being kept up to date. The
adjective is a reduction over that region. The result is a pixel, which is a
world point, which is a place to walk to.

```
   "the nearest edge of the rock"
        │
        ▼
   the rock's region in the current frame       a mask, from the vision pass
        │
        ▼
   reduce it by the adjective                   nearest edge -> min depth
        │                                        over boundary pixels
        ▼
   one pixel (u, v)
        │
        ▼
   unproject through the camera pose            + depth from a vmap raycast
        │
        ▼
   a point on the rock's surface                which is NOT walkable
        │
        ▼
   snap to the navigation mesh                  the nearest reachable point
        │
        ▼
   path there
```

### The adjectives split by what they cost

This is the part worth knowing before building anything: **most spatial
adjectives need no depth at all.**

| Adjective | Reduction | Needs depth |
|-----------|-----------|-------------|
| lowest | largest v | no |
| highest | smallest v | no |
| leftmost | smallest u | no |
| rightmost | largest u | no |
| centre | centroid, snapped to a real pixel | no |
| closest | smallest depth | **yes** |
| furthest | largest depth | **yes** |
| nearest edge | smallest depth among boundary pixels | **yes** |

The image-space ones are free — they are a scan of a mask. The depth ones cost
one vmap raycast per candidate pixel, which for a boundary of two hundred pixels
is two hundred rays against a BVH the server already maintains for line of
sight. That is nothing, and it is only paid when the adjective asks for it.

So a creature saying *the lowest part of the rock* costs a scan, and one saying
*the near edge* costs a scan plus a few hundred rays. Neither costs a depth
buffer, which is why issue 1010 does not need one.

### The snap is not a detail

An unprojected pixel lands **on the surface of the thing**. The near edge of a
rock is a point on the rock. Walking to it means walking into it.

The navigation mesh — mmaps, which the server already loads and already uses to
move creatures — answers "the nearest point to this that something can stand
on". Without that step, every one of these instructions means *walk into the
object you were looking at*, and it will look like the pathfinder being broken
rather than like the aim being right and the destination being unreachable.

The failure has a second form worth guarding: the nearest standable point may be
on the **far side**. A rock between the creature and its own answer produces a
creature that walks all the way around. Whether that is wrong depends on whether
the creature wanted the near edge or wanted to get near the edge, and those are
different instructions in the same words.

### Regions are kept up to date, so the answer moves

The rock does not move; the creature does, and the camera does. So *nearest
edge* resolves differently from a different standing point, and correctly so —
the near edge is near relative to somebody.

Which means a resolution is only valid for the frame it was taken from. Pairing
a pixel with a stale camera pose puts the point somewhere the creature never
looked. Every resolved point carries the frame it came from, or it carries a
lie.

## Suggested Implementation Steps

1. Write the adjectives as an enum, each stating whether it needs depth. Then a
   caller can find out what a reduction will cost before asking for it, and an
   unknown adjective is refused with the list of real ones.
2. Write the reductions over a mask. Pure, testable, no camera and no world.
3. Wire in unprojection, which already exists, using a supplied depth.
4. Add the vmap raycast as the depth source. Only then do the depth adjectives
   work outside a test.
5. Add the navmesh snap. Test that *go to the near edge of the rock* ends beside
   the rock rather than inside it.
6. Only then make it a tool (issue 1006).

## Open Questions

- **What is a "region", exactly?** A bitmap mask, a polygon, or a bounding box.
  A box makes *nearest edge* meaningless — every box has four and they are all
  flat. A polygon is cheap and loses concavity. A mask is right and is the most
  data to move per object per frame.
- **Does the vision pass give stable identity across frames?** *The rock*
  has to be the same rock as the frame before, or a creature walking toward it
  re-resolves to a different rock each turn and never arrives.
- **What if the thing is not in the current frame?** It was there a moment ago
  and the creature turned. Either the last known point is used, which can be
  stale, or the creature has to look again first — which is a tool call, and
  arguably the honest answer.
- **Are there adjectives that need more than one frame?** *Behind* and *the other
  side of* cannot be resolved from one viewpoint at all.
- **Can two adjectives compose?** *The lowest part of the near edge* is a
  reduction over the result of a reduction, which the shape here supports and
  nothing yet asks for.

## Related

- `src/041-vision/043-adjectives.lua` — the closed set, and what each costs
- `src/041-vision/044-regions.lua` — the reductions
- Issue 1009 — where the frames and the masks come from
