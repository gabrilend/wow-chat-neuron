# 407 — Guards Fan Out and Take the High Ground

## Status
- Phase: 4 (Company)
- Blocked by: 405 (the garrison), 406 (garrison persistence)
- Related: 604 (jumpable spacing) shares the terrain-height machinery

## Current Behavior

The garrison, as designed in issue 405, holds a position. All of it, on one
coordinate, in a clump. That is a watch in the sense that they are there, and
not in any sense that looks like watching.

## Intended Behavior

> use this when we are logged out, creating guards who fan out and climb nearby
> high points. Archers fire from these. Guardtowers are ideal.

When a garrison forms, its members do not stand where you left them. Each takes
an arc, searches it for high ground, climbs the best thing it finds, and holds
*that*. The camp becomes a picket rather than a pile.

- **Ranged members prefer height.** Elevation buys sight line and a downhill
  shot, and it is the difference between an archer and a person holding a bow.
- **Guard towers are ideal** — and *ideal* rather than *required*, because a
  tower is simply the best available answer to the search. Found in range, it is
  taken. Absent, a hill will do.
- **When there is no high ground worth having, build some.** Phase 6 can place
  a platform. A platform is a peak somebody made, and the obelisks that can be
  jumped between are a guard tower nobody had to find.

### The search is a wave, not a scan

Finding high ground by checking every point in a radius is correct, expensive,
and — the part that disqualifies it — impossible to interrupt. It either
finishes or yields nothing.

The search used here is the wave search written up in
`notes/wave-search-and-the-fanning-guard.md`: solve small, walk the answer
outward along a sine wave, sample sparsely like a dashed line, propagate so
each pass falls in the last pass's gaps, and stop whenever you like because the
best answer so far is always available.

Three properties matter for this use:

1. **It yields.** Each pass is a slice; the search resumes where it stopped.
   Inside a worldserver's tick budget, anything that blocks is a stutter
   everyone sees.
2. **It finds things early.** A sine-swept dashed line crosses a wider band than
   a straight solid one for the same number of samples, so the peak tends to
   turn up before the search is finished.
3. **It reports distance, not just presence.** A sample that hits carries the
   wave's amplitude at that moment, so the answer is "high ground, nine yards
   left of straight ahead" rather than "high ground somewhere".

### Which hand

The resident hand. Terrain height needs the map data, which only the worldserver
has loaded, and the search must yield between passes, which only something
inside the tick loop can do.

This is the first operation in the project that is genuinely a *standing
behavior* rather than an edit, and it is the reason the resident hand exists.

## Suggested Implementation Steps

1. Write the wave walker as a pure function of its own state: given amplitude,
   phase, distance walked, and a step, return the next sample point and the next
   state. Pure means testable without a game.
2. Write the height sampler against the map object, and the peak accumulator
   that keeps the best sample seen and how far off-axis it was.
3. Wrap the two in a coroutine that yields every N samples, and put it on a
   scheduler that gives each resumable search a slice per tick.
4. Write arc assignment: divide the garrison among directions. Start with an
   even division and expect it to be wrong (see open questions).
5. Write the climb: path to the chosen peak, and hold it. Reuse the garrison's
   existing return-to-post behavior so a guard that dies comes back to *its*
   peak rather than the camp.
6. Write the fallback into phase 6: no peak worth taking within the search
   radius becomes a request to place one.
7. Write tests for the wave walker's coverage — that consecutive passes do fall
   in each other's gaps, which is the entire claim the algorithm rests on.

## Open Questions

- **What amplitude-to-wavelength ratio?** Too flat is a straight line with extra
  steps; too steep and consecutive samples are so far apart laterally that the
  dashes never fill in. There is a right ratio and it is probably derivable from
  the sample spacing rather than guessed.
- **How does a guard pick its arc?** Even division is obvious and probably
  wrong, because good terrain is not evenly distributed and two guards on one
  excellent ridge beats one guard searching a lake.
- **When does a search stop?** "Covered the whole space" defeats the purpose.
  Diminishing returns — a pass that fails to improve the best answer — is the
  likely rule and is a guess.
- **Line of sight, or just height?** The engine can check line of sight.
  Whether a guard should verify it before committing to a peak or just take the
  high ground and find out is a gameplay question wearing technical clothes.
- **Do the guards re-search?** The world changes; someone builds something.
  A watch that never looks up again is cheaper and slightly sad.

## Related

- `notes/wave-search-and-the-fanning-guard.md` — the algorithm, and where it
  came from
- Issue 405 — the garrison this makes spatial
- Issue 604 — jumpable spacing, which needs the same terrain-height machinery
