# 018-bestiary.lua

`world.creatures` — what kinds of thing can be in the world, and which suit a
given level. Covers this file and `017-creature-types.lua`.

**The first read in the project to carry a declaration**, and therefore the
first word a model can use to *look* at anything. Before it, every registered
operation changed something.

Reads `creature_template` — the species list. Not `creature`, which is where
individuals stand.

## Functions

### `Bestiary.find(handle, args) -> rows | nil, why`
`{ type, level, name, rank, limit }`. Returns rows; renders nothing.

### `Bestiary.run(handle, args)` — what the registry calls. A read has no plan and no apply.
### `Bestiary.describe(found, args) -> string`

## The two enums

`CreatureTypes.kind` (13 members) and `CreatureTypes.rank` (6). Numbers read out
of `SharedDefines.h:2620` and `:2962`, verified 2026-09-04. A wrong type number
returns beasts when somebody asked for undead, and the answer looks entirely
reasonable — which is why they are checked against the header rather than
remembered.

**Read `.id`, not `.index`.** And on ranks, `.id` is not difficulty: rare is 4
and world boss is 3. `.worth` is the difficulty.

## `fightable` is this project's judgment, not the game's

`creature_template` holds tens of thousands of rows and most are quest props,
invisible triggers and scenery. Eight of thirteen types are marked fightable;
the filter also demands `modelid1 > 0` and `minlevel > 0`.

Without it, a model handed the raw list spawns a squirrel, or something with no
model at all. It is a heuristic and is stated as one: it will exclude things
somebody eventually wants, and the fix is here rather than in whatever was
surprised by it.

## Level is a band, not a number

A template has `minlevel`/`maxlevel`, so `level = 12` means *templates whose
band contains 12*. Asking `minlevel = 12` instead returns almost nothing and
reads as an empty database rather than as the wrong question.

## Ordinary creatures unless asked otherwise

`rank = 0` by default. A level band full of world bosses is not a level band.
