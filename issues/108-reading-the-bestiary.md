# 108 — `world.creatures`: Reading the Bestiary

## Status
- Phase: 1 (Reach) — a read, like everything else in this phase
- Blocked by: 101 (deployment handle), 102 (the cold hand)
- Blocks: 607 (`world.spawn`) — you cannot place what you cannot name

## Current Behavior

**Built.** `src/018-bestiary.lua`, with `017-creature-types.lua` beside it for
the two enums. It registers as `world.creatures` and is the **first read in the
project to carry a declaration** — before it, a model could act on the world and
could not look at it.

The type and rank numbers are read out of `SharedDefines.h:2620` and `:2962`
rather than remembered, and both are verified.

The query itself has not been run: MySQL is not up in this session, so what is
proven is the numbering, the declaration, and the rendering of an answer. The
`fightable` filter — a model handed raw `creature_template` picks a squirrel or
something with no model — is this project's judgment rather than the game's, and
is stated as one in the source.
## Intended Behavior

Find creature kinds by what they are and what level they are for.

```
neuron creatures --type undead --level 12
neuron creatures --name "skeleton" --limit 20
```

### The columns that matter

`creature_template` in the world database:

| Column | Holds |
|--------|-------|
| `entry` | the id `world.spawn` needs |
| `name` / `subname` | what it is called |
| `minlevel` / `maxlevel` | the band it is built for |
| `type` | the creature type — **undead is 6** |
| `rank` | normal, elite, rare, boss |
| `faction` | who it fights |

The type numbers are the core's, from `SharedDefines.h`'s `CreatureType` enum,
and belong in an enum beside the others rather than as a number at the point of
use — the same reasoning that put slots and stats there. Getting one wrong
returns beasts when somebody asked for undead, which is not an error anywhere.

### Level is a band, not a number

A template has a range, so "level 12" means *templates whose band contains 12*,
not *templates whose level is 12*. Asking the second question of this table
returns almost nothing and looks like the database being empty.

### Rank changes what an encounter is

A normal creature and an elite of the same level are very different fights. A
request for "successive encounters, level progressing" that ignored rank would
produce a smooth level curve and a wildly uneven difficulty curve, which is the
opposite of what was asked for. Rank has to be visible in the answer for a model
to compose sensibly with it.

## Suggested Implementation Steps

1. Add a `CreatureTypes` enum, read out of the core's own header rather than
   remembered.
2. One parameterised query with optional filters, ordered by level then name.
3. Return rows as data, not as rendered lines — the same reasoning that made the
   roster answer structured so names could be class-coloured.
4. Declare it `read`, hand `cold`, so it works with the world down. This is the
   first read to get a declaration and therefore the first to prove reads work
   in the registry at all.

## Open Questions

- **Which of the thousands is a good encounter?** `creature_template` holds tens
  of thousands of rows, most of them quest props, critters, and triggers with no
  model. A model handed the raw list will pick invisible ones. Some notion of
  *fightable* is needed and nothing in the table states it directly.
- **Does faction matter to the asker?** An undead creature of the player's own
  faction will not fight them. Filtering by hostility needs the player, which a
  read of a template alone does not have.
- **Should this be one word or two?** Searching by name and filtering by level
  band are different questions asked at different moments.

## Related

- Issue 607 — `world.spawn`, which takes the `entry` this returns
- `docs/vocabulary.txt` — the reading section this joins
