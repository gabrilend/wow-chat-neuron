# Wave Search, and the Guards Who Fan Out

*Design note. The algorithm came first and the use case came with it, in the
same breath, which is usually a sign that both are right.*

## The Problem It Solves

You have a space and a question about that space. "Where near here is high
ground?" "Does this line from A to B hit anything?" "Where can a platform go
that a player could actually jump to?"

The obvious way to answer is to check every spot. That is correct, expensive,
and — the part that actually matters — **it does not degrade well**. A check
over every spot either finishes or it does not. There is no useful partial
answer, so it cannot be interrupted, cannot run in the background, and cannot
report progress that means anything.

## The Algorithm, As Given

> calculate the answer in a small space, repeat it on a sine wave toward the
> destination place. then, propagate the wave, and keep retrying until the
> entire space is covered. That way we don't have to check every single spot
> all at once, and it continues processing like a coroutine in the background.
> the idea is, we test like a dashed line filling in itself - there's more
> chance of an intersection if we do it like that. Then, we can better
> understand distance.

Unpacked into mechanism:

1. **Answer it small, first.** Solve the question exactly in a tiny
   neighbourhood, where exact is cheap.

2. **Walk the answer outward along a sine wave** toward where you are actually
   headed. Not a straight line — a line that oscillates across the straight
   line, sampling to either side as it goes.

3. **Sample sparsely along that wave** — a dashed line, not a solid one. Gaps
   on purpose.

4. **Propagate.** Widen the wave, shift its phase, and run again, so the new
   dashes fall in the previous run's gaps. The dashed line fills itself in.

5. **Keep going until the space is covered** — or until you have an answer, or
   until somebody stops you, because you can be stopped at any point between
   passes and what you have so far is still meaningful.

## Why the Dashes Are the Point

A solid scan-line covers a corridor exactly as wide as the line. A dashed line
swept along a sine wave, at the same sampling cost, covers a *band* — because
the oscillation carries the samples across the whole width of the corridor
rather than down its middle.

So for the same number of checks, a sine-swept dashed line **crosses more
distinct territory** than a straight solid one. If what you are looking for is
an intersection — a wall, a peak, a gap — you are more likely to hit it early,
and early is the whole game when you intend to stop as soon as you have an
answer.

The phrase that carries it: *"there's more chance of an intersection if we do
it like that."* That is a statement about the geometry of coverage, and it is
correct.

## Why It Understands Distance Better

A straight-line probe tells you *whether* something is in the way. A wave probe
tells you **how far off the straight path you had to go to find it**, because
the sample that hit carries the wave's amplitude at the moment it hit.

That is a richer answer for free. "There is a cliff" becomes "there is a cliff,
and it is nine yards left of the direct route", which is the difference between
knowing you are blocked and knowing how to go around.

## Why It Is a Coroutine

Each pass is a complete unit of work that leaves the search in a resumable
state: the wave's current amplitude, phase, and how far along it has walked.

So the search **yields between passes**. It costs a slice, gives the frame back,
and picks up where it stopped. A long search becomes background work rather than
a stall, and a search that is no longer needed is simply never resumed.

This is the property that makes the whole thing usable inside a game server's
tick budget, where anything that blocks is a stutter everybody sees.

## What It Is For: The Guards Who Fan Out

> use this when we are logged out, creating guards who fan out and climb nearby
> high points. Archers fire from these. Guardtowers are ideal.

This is the garrison, made spatial.

The garrison (phase 4) says: when you log out, your party does not dissolve.
The bots hold the position, fight, die, respawn, and come back to the same spot.

This note says **what they do while holding it**. They do not stand in a clump
on the coordinate you left them on. They *fan out*, and each one searches its
own arc for high ground, and climbs it.

- **Wave search finds the high ground.** Each guard runs its own wave outward
  from the camp, sampling terrain height. Sparse, cheap, interruptible, and
  running in the background while the game does everything else.
- **Height is the thing being searched for**, so the sample is a height query,
  and the answer is the best peak found so far — which improves as the wave
  propagates and is usable before it finishes.
- **Archers fire from the peaks.** Elevation is a real advantage: longer sight
  lines, and a downhill shot.
- **Guard towers are ideal**, and they are *ideal* rather than *required*
  because a tower is simply the best possible answer to the search. If one is
  in range, the wave finds it and the guard climbs it. If not, a hill will do.

And the loop closes with phase 6: if there is no high ground worth taking,
**construction can place some.** A platform is a peak you built. The obelisks
you can jump between are a guard tower nobody had to find.

## The Shape of the Connection

```
   you log out
        │
        ▼
   the garrison holds        (phase 4 — the watch does not dissolve)
        │
        ▼
   each guard fans out       (this note — an arc each, not a clump)
        │
        ▼
   wave search for height    (this note — dashed, sine-swept, resumable)
        │
        ├── found a peak  ──► climb it; archers shoot from it
        │
        └── found nothing ──► construction places one   (phase 6)
        │
        ▼
   you log back in, and some of them died while you were gone
```

## Open Questions

- **What is the sine wave's amplitude relative to its wavelength?** Too flat and
  it is a straight line with extra steps; too steep and consecutive samples are
  so far apart laterally that the dashes never fill in. There is a ratio that is
  right and it is probably derivable from the sample spacing.
- **How does a guard pick its arc?** Evenly dividing the circle among the
  guards is the obvious answer and is probably wrong — the interesting terrain
  is rarely evenly distributed, and two guards searching the same good ridge is
  better than one guard searching a lake.
- **Does the search run in the worldserver or outside it?** Terrain height
  queries need the map data, which the worldserver has loaded. That argues for
  the resident hand. But a long background search is exactly what the resident
  hand's tick budget is worst at, which argues for precomputing outside and
  handing in a table.
- **What counts as "the entire space is covered"?** A termination condition of
  "every spot has been sampled" defeats the purpose. It should probably
  terminate on diminishing returns — when a pass stops improving the best answer
  — but that is a guess.
- **Do archers need line of sight, or just height?** The engine has a line-of-
  sight check. Whether the guard should verify it before committing to a peak,
  or just take the high ground and find out, is a gameplay question more than a
  technical one.
