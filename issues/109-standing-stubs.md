# 109 — Standing Stubs: A Path That Works and Says It Is Not the Thing

## Status
- Phase: 1 (Reach) — foundational; anything may declare one
- Blocked by: nothing
- Blocks: 1201 (`creature.reskin`), and every prototype built ahead of its hard part

## Current Behavior

The project has one position on incompleteness and it is absolute: **a fallback
is a warning and a warning is an error.** Silently doing the second-best thing
is how somebody spends an afternoon on a change that never happened.

That position is right and it has no word for a real, different thing.

Sometimes the placeholder is the point. Prototyping *"change that goblin"* with
models the game already ships is not a fallback — it is the only way to build
the asking, the plan, the confirmation and the receipt before anybody has
written a scraper. Refusing to build the surrounding nine-tenths until the
hardest tenth exists is not caution; it is never starting.

Today such a path would be indistinguishable from a finished one, and the note
saying otherwise would live in a comment nobody reads.

## Intended Behavior

A **stub** is a working path that announces itself every time it is used.

```
[ STUB ] picking a creature's appearance
  doing        using a display the game already ships
  instead of   finding one on open-game-art and converting it
  go build it  issues/1203-the-asset-scrapers.md
```

Four things, all required:

| | |
|---|---|
| `what` | the job, in a person's words |
| `doing` | what this actually does |
| `instead_of` | what it stands in for |
| `issue` | **the file to go and work on** |

The fourth is the one that makes the difference between an announcement and a
comment. A notice with nowhere to send somebody is a notice nobody can act on,
so a stub missing it is refused at declaration.

### Where it appears

Three places, because three different people need it at three different moments:

- **On the terminal**, the first time it runs — whoever is working right now.
- **In the plan description** a person reads before agreeing — so agreeing to
  something built on a placeholder means having been told.
- **In the summary at the end of a run** — what this session leaned on, with
  counts.

### Announced once, counted always

The first use writes to the terminal; the rest are silent and tallied. A plan
that spawns forty creatures would otherwise print the same four lines forty
times, and four lines printed forty times is four lines nobody reads.

The count is not lost — the end-of-run summary reports it. **Loud once, honest
always.**

### Declared at module scope, noticed at point of use

Because declaration is separate from use, every stub in the project can be
listed without running anything. The mechanism becomes a to-do list **generated
from the code** rather than kept beside it — and a to-do list kept beside code
is a to-do list that disagrees with it.

### What a stub is not

Not a `TODO` comment: those are invisible at runtime. Not a fallback: a fallback
hides that the good path failed, where a stub says the good path was never
built. Not a feature flag: nothing switches, because there is nothing to switch
to yet.

## Suggested Implementation Steps

1. Refuse a declaration missing any of the four fields, naming which.
2. Announce on first use only; count every use.
3. Return the block from `notice()` so a caller can embed it in a plan without
   formatting it again.
4. Write an end-of-run summary that lists only what was actually leaned on —
   not everything unfinished, which is a different and much longer list.
5. Add a `scripts/stubs` that loads the tree and prints every declared stub,
   used or not.
6. Put the summary at the end of the command line and in the chat window's
   answer, so it is seen by somebody who did not read this file.

## Open Questions

- **Should a stub ever refuse to run?** A `--no-stubs` mode would prove which
  parts of the project are real. It would also make the prototype unusable,
  which is the point of the prototype.
- **Do stubs belong in receipts?** A receipt records what was done to the world.
  That a display id came from the shipped set rather than from a converted asset
  is arguably part of what was done, and arguably clutter.
- **How does a stub get retired?** Nothing currently notices that the issue it
  names was completed, so a finished feature can keep announcing itself as a
  placeholder — which teaches everybody to ignore the announcements.

## Related

- `src/054-stubs.lua`
- Phase 12 — Likeness, which is built almost entirely out of these
