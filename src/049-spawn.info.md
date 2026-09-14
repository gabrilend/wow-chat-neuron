# 049-spawn.lua

`world.spawn` — put creatures in the world. The first word that **creates**
anything.

## Functions

### `Spawn.plan(handle, args) -> plan | nil, why`
`{ creature (entry number), place, count, spread, permanent }`. Reads freely,
writes nothing. One step per creature, each carrying both its resident form and
its cold form.

### `Spawn.script(entry, map, x, y, z, orientation, permanent) -> string`
The Lua installed into the running worldserver.

### `Spawn.describe_plan(plan)` · `Spawn.apply(handle, plan, state) -> receipt`

## Why resident, which is the whole design

| Hand | Can it? | |
|------|---------|---|
| live | **no** | `.npc add` spawns at the *caller's* position, and a SOAP caller has no body in the world. Same limit `003-live-hand.lua` records for `gobject add`. |
| cold | writes a row | The worldserver loads spawns **when a grid loads**. A grid somebody is standing in is already loaded and will not reload — so the creature exists in the database and not in the world, possibly forever. Write succeeded, tool reported success, nothing appeared. |
| **resident** | **yes** | ALE's `PerformIngameSpawn` runs inside the worldserver. The creature is there when the call returns. |

Hands are `{ resident, cold }` — resident because it works now, cold as the form
that survives the world being down and whose plan line says plainly that nothing
appears yet.

## The ground is read, not taken

The installed script asks the map for its height, probing from ten yards above.
A place's recorded `z` is where a **player** teleports to; on a dock or a bridge
that is not the ground, and a creature spawned there hangs in the air or stands
inside the terrain. No ground within forty yards means open water or a hole, and
the script refuses loudly in the server log rather than dropping a creature into
the sea — where the failure is reported as the spawn silently not working.

## The scatter is a golden-angle spiral

Bearing turns by `π(3−√5)` each time; radius grows as `√(index/count)`.

A circle puts everybody the same distance out and reads as a summoning ritual.
Random clumps and leaves gaps. The golden angle fills outward evenly with no two
at the same bearing, so it looks like a group of things that happen to be
standing there. Square-root radius keeps area per creature even rather than
crowding the middle.

## Forty is the ceiling

More than that in one place is a crowd nobody can fight. A larger encounter is
several spawns at several places — which is also how it becomes something
somebody walks *through* rather than something that surrounds them.

## Unverified

No creature has appeared in a world. No worldserver has run in any session that
touched this file, so the resident mechanism's reload is unproven here too.
