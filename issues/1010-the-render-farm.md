# 1010 — The Render Farm: Where the Pictures Come From

## Status
- Phase: 10 (Narration)
- Blocked by: nothing in neuron; blocked on a decision about what draws
- Blocks: 1009 (seeing instead of querying), and through it 1006 and 1007

## Current Behavior

**Nothing in this deployment can produce an image.**

The worldserver is a simulation, not a renderer. It holds positions, model ids,
map ids and creature templates; it has no geometry, no textures, no camera and
no framebuffer. Drawing has always been the client's job, and the client is a
separate program on somebody's desktop.

So there are no screenshots, and there is no code path that could be extended
into taking one. This is not a missing feature — it is a missing half of the
system.

## Intended Behavior

**A small pool of camera characters, partitioned by map, teleporting to where a
shot is wanted and capturing there.**

The renderer is the real game client. Nothing has to be rebuilt, nothing has to
parse an archive, and the pictures are correct because they are the pictures the
game actually draws.

### One per loading screen

A camera is a logged-in character: invisible model, first person, no body in
anybody's way. It is told where to stand, it stands there, it captures, and it
moves on to the next creature in its map.

**The partition is by map because a map boundary is a loading screen.** Moving
within Kalimdor is a position update. Moving from Kalimdor to Northrend is a
full world load, seconds long. So a camera never leaves its map, and the pool
holds at least one per map that has creatures in it — about four for the open
world, plus one per instance that matters.

Several per map is allowed and is the throughput lever. Nothing about the design
says one; the design says **never across**.

### Batch by creature, not by shot

The expensive part is not the capture. It is arriving somewhere and waiting for
the scene to be there.

So a camera teleports **once per creature** and takes every frame that creature
wants from that spot — all its tracked objects, plus anything it is thinking of
examining — before it jumps to the next. Rotating in place is free; arriving is
not.

```
   for each creature in this map:
       teleport to its camera pose        ← the expensive step, paid once
       wait for the scene to be there     ← the unknown, see below
       capture every shot it wants        ← cheap, rotate in place
   then the next creature
```

### The arithmetic, restated

With batching, the cost is one arrival per creature per loop turn, not one per
shot:

```
    arrivals per second  =  C / S / cameras
```

128 creatures on a 30-second loop is **4.3 arrivals a second across the pool**.
One camera per map has to sustain that alone if all 128 are in one map; four
cameras in that map bring it to roughly one a second each, which is comfortable
if a scene settles in well under a second and impossible if it does not.

That single unknown — **how long after a teleport is the frame valid** — decides
the size of the pool and therefore whether this is cheap or merely possible. It
is the first thing to measure and it needs no other part of this built.

### Colour from the client, depth from the server

A window capture gives colour and no depth buffer. Unprojection needs depth
(issue 1009), so it comes from the other side:

| | Source | Cost |
|---|---|---|
| colour | the client's own frame, captured externally | one screenshot |
| depth | a **vmap raycast**, server-side, from the camera pose | one ray per pixel asked about |

The server already owns the collision geometry and already casts rays through it
for line of sight. So depth is answered **on demand, for the pixels somebody
actually pointed at**, rather than rendered for every pixel and thrown away.

That inverts the usual cost. A full depth buffer is expensive and mostly unused;
a few hundred rays against a BVH is nothing. And it means the two halves of a
frame come from the two places that are each already good at their half.

### What this does not need

No archive parsing, no model loading, no rasteriser, no scene graph, no animation
system. All of that was the price of owning the renderer, and owning the renderer
turned out to be unnecessary because there is one already running that can be
told where to stand.

## Related

- Issue 1009 — what the images are for
- Issue 1008 — relevance, which is the lever on `T`
