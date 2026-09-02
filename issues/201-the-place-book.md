# 201 — The Place Book

## Status
- Phase: 2 (Displacement)
- Blocked by: 102 (cold hand), 105 (reading the world)
- Blocks: 203 (teleport), 603 (arrangements), 1101 (queststorydungeon anchoring)

## Current Behavior

Nothing exists. A caller wanting to move somebody must supply a map id and three
floating-point coordinates, which nobody says out loud and nobody remembers.

## Intended Behavior

Places have **names**. `ratchet`, `menethil-harbor`, `the-ridge`. A name resolves
to a map, three coordinates, an orientation, and a sentence about what it is.

### Most of it already exists

The world database ships `game_tele` — **1,989 named locations**, verified on the
live deployment. It is the table AzerothCore's own `.tele` command reads.

That is the place book. It does not need inventing, only reading.

And it produces a symmetry that shapes the whole of phase 2: the live hand's
`tele name <character> <location>` takes **exactly these names**. So one name
works through both hands, differently:

| Hand | What it does with the name |
|------|----------------------------|
| live | Passes it straight through to the game master command |
| cold | Looks up its coordinates and writes them onto the character row |

No translation layer, no mapping table, no chance of the two hands disagreeing
about where `ratchet` is. They disagree only if the database disagrees with
itself.

### Project places, on top

A queststorydungeon needs anchors the game never heard of — `the-ridge`,
`camp-north`, `third-obelisk`. These live in a project-owned table alongside the
game's, and they are the ones that can be created, moved, and deleted.

Resolution order is **project first, then game**, so a project place may shadow a
game one deliberately. A shadowing name is reported when it is used, because
silently getting a different Ratchet than the game means is exactly the sort of
thing that produces a confused hour.

Project places cannot be used by the live hand's `tele name` — the game does not
know them. An operation resolving to a project place must therefore use the cold
hand, or write the coordinates through a command that takes coordinates rather
than a name. That constraint belongs to the place, so a place record carries
whether the game knows it.

### Names are matched forgivingly

The game's names are `MenethilHarbor`, `TheBarrens`, camel-cased and unspaced.
Nobody types that. Matching lowercases and strips punctuation on both sides, so
`menethil harbor`, `Menethil-Harbor`, and `menethilharbor` all find it.

An ambiguous match returns **all** the candidates rather than picking one. There
are 1,989 names and many share prefixes; guessing which one somebody meant and
teleporting forty characters there is not a recoverable mistake.

## Suggested Implementation Steps

1. Write the reader over `game_tele`: id, name, map, x, y, z, orientation.
2. Write the normaliser used on both sides of a comparison, and be sure it is
   the *same function* for both — two normalisers that drift is a lookup that
   works in tests and not in life.
3. Write the project place table and its migration, marked so neuron's own rows
   are distinguishable from anything else that lands in that database.
4. Write resolution: project first, then game, with a report on shadowing and
   the full candidate list on ambiguity.
5. Write `place.list` and `place.show` so a person can find a name without
   opening a database client.
6. Write `place.remember` — capture a character's current position as a named
   project place. This is how `the-ridge` comes to exist: you stand on it and
   name it.
7. Write the `.info.md`.

## Open Questions

- **Should project places be per-deployment or global?** A name like `the-ridge`
  means a coordinate in one world. Carrying it to another world is exactly what
  a queststorydungeon must do, and exactly what a place book must not do
  silently.
- **Does a place carry a facing?** `game_tele` has orientation. Arriving all
  facing the same way looks arranged; arriving facing outward looks like a
  guard post. Phase 2's formation work may want to override it.
- **What about places on instance maps?** `game_tele` contains them. Teleporting
  an offline character into an instance by writing their row is likely to
  produce a character who cannot log in. Needs a guard, and the guard needs to
  know which maps are instances.

## Related

- `docs/datapath-displacement.md`
- Issue 203 — teleport, the first consumer
- Issue 1101 — anchoring an arrangement to a place
