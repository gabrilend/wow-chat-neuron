# 1012 — `camera.orbit`: Flying Around Something Until You Know Its Shape

## Status
- Phase: 10 (Narration)
- Blocked by: 1010 (the camera pool), 1009 (seeing instead of querying)
- Blocks: nothing — this is a capability the narrator reaches for, not a
  foundation anything stands on

## Current Behavior

A camera takes one frame from one place. Issue 1009 places it over a creature's
shoulder aimed at a thing; issue 1010 moves it around a map serving one creature
at a time.

So everything anybody knows about an object is one photograph of it from one
side. What a thing looks like from behind, how tall it actually is, whether the
two shapes touching in frame are one object or two — none of that is
recoverable from a single view, and a narrator asked *what is over there* can
only describe a silhouette.

## Intended Behavior

Send the camera around something in a circle, and work out its shape from what
it blocks.

```
neuron orbit --subject Grast --frames 12 --radius 20 --height 12
```

### The flight

Constant radius, constant altitude, always looking inward and slightly down —
a helicopter, not a dolly. The subject stays centred while the world turns
behind it, which is exactly what makes the frames comparable.

```
                    frame 4
                       │
      frame 5      ╭───┼───╮      frame 3
              ╲    │   ▼   │    ╱
               ╲   │       │   ╱
    frame 6 ────── [subject] ────── frame 2
               ╱   │       │   ╲
              ╱    │       │    ╲
      frame 7      ╰───────╯      frame 1
                  radius R, height H
```

Bearings are evenly spaced: `θ = 2πn/N`. Each pose is the existing
`Camera.pose(position, look_at)` — position on the circle, `look_at` the
subject. Nothing new is needed to aim it.

### Silhouettes superimposed: what actually comes up

The interesting part is not the twelve pictures. It is what survives being laid
over each other.

Every frame gives a **silhouette** — the region the subject occupies. Each
silhouette, combined with the camera pose that took it, is a statement about
space: *everything outside this outline, along this direction, is not the
object.* Twelve such statements from twelve bearings carve a volume out of the
air.

```
   for each point in a grid around the subject:
       project it into every frame        ← Camera.project, which exists
       if it lands OUTSIDE the silhouette in ANY frame:
           it is not part of the object
   what survives all twelve is the shape
```

This is the **visual hull**, and it is the oldest trick in shape reconstruction
precisely because it needs nothing but outlines and known viewpoints — both of
which the orbit produces by construction. No depth, no stereo matching, no
recognition. A point is either blocked from every angle or it is not there.

### What the hull can never see, stated up front

**Concavities.** A bowl carves out as a lump; the inside of a cup is invisible
to every silhouette because nothing along that ray is ever outside the outline.
More frames tighten the hull and never find a hollow.

This is a property of the method rather than a gap in an implementation, and it
should be said in the answer the narrator gets. A narrator that believes it
knows a shape exactly will describe a doorway as a wall.

### What twelve frames reveal that one cannot

- **Footprint and height**, in yards, rather than in pixels.
- **One thing or two.** Two shapes touching in one frame separate in another.
- **What is behind what.** Something visible from the north and absent from the
  south is occluded, and the direction it is occluded from is known.
- **How it reads from an angle nobody photographed** — which is the payoff, see
  below.

The **disagreements between frames carry more than the agreements.** A pair of
silhouettes that cannot both be true of one convex object means two objects, or
a concavity, and either is worth saying.

### Describing a view nobody took

With a hull and twelve poses, the question *what would this look like from where
the player is standing* is answerable without going there. Project the hull from
the player's position; see what occludes what.

That is what the orbit is for. The narrator is describing events from a person's
perspective, and that person is somewhere no camera was. The orbit does not
produce the player's picture — it produces enough to **imagine** it correctly,
which is a different and cheaper thing.

### The cost, and the tension with how cameras are normally used

An orbit is **N arrivals for one subject**. Issue 1010's whole batching rule is
the opposite — one arrival per creature, then every shot that creature wants
from that spot, because arriving is the expensive step.

So an orbit is the costly exception. Twelve frames of one rock is twelve
teleports and twelve waits for the scene to settle, during which the camera
serves nobody else in its map. It must be rare, deliberate, and asked for —
never something perception does on its own because a thing looked interesting.

Reserve it for what the narrator genuinely needs to understand: a place somebody
is about to arrive at, a structure that was just built, a thing a person asked
about directly.

## Suggested Implementation Steps

1. Write the flight as poses only, with no camera and no world. It is a circle
   and a `look_at`, both already in `042-camera.lua`, and it is testable to the
   yard.
2. Take the frames through issue 1010's pool, as one job rather than N — a
   camera that gives up an orbit halfway leaves a hull carved from four
   viewpoints and no note saying so.
3. Carve the hull with `Camera.project` over a coarse grid. Coarse first: a hull
   accurate to a yard is enough to say *waist-high and about four yards across*,
   which is what a narrator says.
4. Report the hull as measurements and relationships, not as geometry. The
   narrator needs "roughly cylindrical, three yards wide, taller than a person,
   with something smaller against its north side" — not a voxel list.
5. Say what could not be seen. Concavities, and any bearing whose frame failed.

## Open Questions

- **How is the silhouette obtained?** The subject is centred by construction, so
  a region grown from the centre is one answer and a recognition pass is
  another. The clean answer — render with and without the subject and difference
  them — is unavailable, because the camera cannot make a creature vanish.
- **What radius, and what height?** Too close and the subject leaves frame at
  some bearings; too far and it is a few pixels. Both probably scale with how
  big the thing turns out to be, which is not known until after the orbit.
- **How many frames?** Twelve is a guess. The hull tightens with N and the cost
  is linear in it, and the elbow of that curve is an empirical question nobody
  has looked at.
- **What if the subject moves?** Twelve arrivals take time. A creature that
  walks away mid-orbit produces silhouettes of a thing that was never in one
  place, and the hull carved from them is of nothing.
- **Can two subjects share an orbit?** Two things near each other are one flight
  and two hulls, if the silhouettes can be told apart — which is cheaper by half
  and is exactly the case where telling them apart is hardest.
- **Should the frames be kept?** A hull is small and a dozen images are not. If
  they are discarded, the hull cannot be re-carved when the method improves.

## Related

- `src/041-vision/042-camera.lua` — `pose` for the flight, `project` for the carve
- Issue 1010 — the pool this competes with, and the batching rule it violates
- Issue 1007 — the narrator, which is who this is for
