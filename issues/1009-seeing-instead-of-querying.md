# 1009 — Seeing Instead of Querying

## Status
- Phase: 10 (Narration)
- Blocked by: 1010 (the render farm — there is nothing to look at without it),
  1005 (the scratchspace)
- Blocks: 1006 (NPC tools), 1007 (the resident narrator)

## Current Behavior

A creature learns what is near it by asking the database. `world.roster`,
`world.places`, a `SELECT` against `gameobject` — every one of neuron's reads is
a query, and a query returns rows.

That is right for an operator reaching in from outside, and wrong for something
standing in a room. A row says a barrel exists at coordinates. It does not say
the barrel is behind the door, or half in shadow, or that there are four of them
in a row and the fourth is knocked over.

## Intended Behavior

**Things are generated from images, not from data values.** A creature's
perception is a camera and a vision pass, and the world model it builds is
whatever it recognised — not whatever the database holds.

This inverts the project's founding assumption for exactly one consumer, and the
inversion is the point:

| | Operator reads | Creature perception |
|---|---|---|
| Source | rows | pixels |
| Completeness | everything that exists | what is visible from here |
| Can be wrong | no | **yes, and that is correct** |
| Notices arrangement | never | naturally |
| Notices occlusion | never | naturally |

A creature that queries knows about the barrel behind the wall. A creature that
looks does not, and will be surprised by it, and being surprised is a thing a
creature does.

### The camera, per object

One image per object the creature is tracking, taken over its own shoulder:

```
                 camera
                   ▲  up 2 ft above the eye
                   │
      back 1 ft ───┤   side 1 ft, left or right
                   │
              [character]  ──────────────►  [object]
                                  aimed at
```

Offsets, in yards, since a WoW yard is the world unit and a foot is 0.3048 of
one:

| Axis | Feet | Yards | Relative to |
|------|------|-------|-------------|
| back | 1 | 0.3048 | along the reverse of the view axis |
| up | 2 | 0.6096 | above the character's **eye**, not its feet |
| side | 1 | 0.3048 | perpendicular to the view axis |

The camera aims at the object, not along the character's facing. Which means
the character's own body sits in the near frame and the object sits centred
beyond it — the shot says *I am looking at that*, in one frame, which is what
makes first-person narration line up with what is being narrated.

**Up is measured from the eye, and the eye is not a constant.** This deployment
runs mod-grownup, which scales player models by level, so a level 4 character
and a level 40 one have their eyes at different heights. A fixed eye height
produces a camera inside a tall character's skull.

**Which side.** Proposed rule: the side *away* from where the object sits
relative to the character's facing — if the object is off to the right, the
camera goes left. The reasoning is that a creature turns toward what it looks
at, so the far-side camera catches the turn rather than the back of a turned
head. This is a guess about how the frames will read and should be checked by
looking at actual renders rather than reasoned about further.

### Aiming by looking at previous pictures

The camera for a new shot is **not** computed from world coordinates. It is
derived from imagery already taken: something in a wide frame looks worth
examining, and a new camera is projected from just above it.

The mechanism that makes this concrete is unprojection. Every render keeps its
depth buffer, so a point named in image space — *that thing, there* — becomes a
point in the world:

```
    a pixel (u, v) in a frame
      + that frame's camera pose
      + the depth at that pixel
      ──────────────────────────►  a world position
                                     └─► a new camera, placed just above it
```

So "point at that" is a complete instruction, and nothing had to know what the
thing *was* in order to look at it more closely. The creature can examine
something it cannot name.

### Perception proposes, the creature disposes

**Every new object in an undiscovered area gets an atom made for it. Whether it
is kept is the creature's choice.**

That is a fourth stage in front of the memory model rather than a change to it:

```
    vision       candidate atoms, one per recognised thing, free
      │
      │  `note` -- an act, and common
      ▼
    ring         N slots
      │
      │  `remember` -- an act, and rare
      ▼
    sheet        forever
```

Candidates cost nothing because seeing costs nothing; a creature that walks into
a room full of things has proposals for all of them. Keeping any is still an act
against a bounded ring, so a room with thirty things in it produces a creature
that noticed thirty and kept four — and which four is the whole of what it is.

### Ranking is part of recognition, not after it

The vision pass returns things *already ordered by how much they want to be
examined*, because a creature does not consider thirty candidates and then rank
them; it notices four things and the rest are background.

What makes something valuable is unspecified and should stay unspecified until
there are real frames to look at. Plausible signals — size in frame, centrality,
motion, unlikeness to its surroundings, unlikeness to what is already on the
sheet — are all guesses, and the last one is the interesting guess, because it
makes a creature notice what is *new to it* rather than what is objectively
prominent.

### The images compete for context like everything else

An image is by far the most expensive thing that can go in a prompt, so the
relevance budget of issue 1008 governs them: a creature mid-conversation
attaches fewer scene frames, because it is paying attention to a person instead
of the room. That falls out of what already exists rather than needing its own
rule.

## Suggested Implementation Steps

1. Write the camera geometry first — pose from subject and target, projection,
   unprojection. It is pure arithmetic, needs no renderer, and is the part with
   real decisions in it.
2. Get **one** frame of anything, from anywhere, before designing further. Issue
   1010 is where that fight is, and until it is won everything here is drawing
   on paper.
3. Feed one frame to a vision pass and see what comes back. The ranking question
   above is not answerable from an armchair.
4. Wire candidates into `note` as proposals rather than writes.
5. Only then do multiple objects, multiple creatures, and the batching of 1010.

## Open Questions

- **How does the creature name a pixel?** Unprojection needs a `(u, v)`. Whether
  a model can reliably point at a location in an image, as opposed to describing
  what is in it, decides whether the aim-from-imagery mechanism works at all.
- **What is the field of view?** It sets how much of the room one frame holds,
  and therefore how many objects one shot can propose. Too wide and everything
  is small; too narrow and a creature has tunnel vision.
- **Does the character's own body belong in frame?** It grounds the "I", and it
  costs pixels. At one foot behind, it costs a great many pixels.
- **What happens when the object moves between the render and the prompt?** The
  frame is a photograph of a moment and the creature acts a moment later. A
  creature reaching for a carrot somebody already took is either a bug or the
  most alive thing here.
- **Is anything else allowed to query?** The tools of issue 1006 resolve targets
  by proximity, which today means a database read. A creature that *sees* a
  carrot but *reaches* by query is using two different worlds, and they will
  disagree.

## Related

- Issue 1010 — where the images come from, which is the hard part
- Issue 1008 — the budget the images compete inside
- `src/041-vision/042-camera.lua` — the geometry
