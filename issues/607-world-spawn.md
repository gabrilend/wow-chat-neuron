# 607 — `world.spawn`: Putting a Creature In the World

## Status
- Phase: 6 (Construction)
- Blocked by: 700 (mechanisms), 108 (reading the bestiary)
- **Not** blocked by 601–606, which are about gameobjects; this shares the phase
  and none of the machinery
- Blocks: the MVP request, which is a sequence of these

## Current Behavior

**Built.** `src/049-spawn.lua`. It registers as `world.spawn`, hands
`{ resident, cold }`, and is the first word in the project that **creates**
anything.

The resident script it installs is generated and parses; the scatter geometry is
exercised. What has **not** happened is a single creature appearing in a world,
because no worldserver has been running in any session that touched this. The
resident mechanism's reload command is still unverified for the same reason.

Two things settled while building it. The ground height is read from the map
inside the installed script rather than taken from the place book, because a
place's recorded `z` is where a *player* teleports to — on a dock or a bridge
that is not the ground, and a creature spawned there hangs in the air. And the
scatter is a golden-angle spiral rather than a circle or a random scatter: a
circle puts everybody the same distance out and reads as a summoning ritual,
random clumps and leaves gaps.
## Intended Behavior

Place one creature of a named kind at a named place.

```
neuron spawn --creature 1501 --place ratchet --plan
```

### The live hand cannot do this, and the reason is already documented

`.npc add` spawns at the **caller's own position**. A SOAP caller has no body in
the world and cannot acquire one, so the command has nowhere to put anything.
This is the same limit `003-live-hand.lua` already records for `gobject add`,
and it is why phase 6 places props through the database rather than by command.

### The cold hand can do it and the creature will not appear

An `INSERT` into `creature` is durable and correct, and the worldserver loads
spawns **when a grid loads**. A grid with somebody standing in it is already
loaded and will not reload, so the monster exists in the database and not in the
world until the area empties or the server restarts.

That is the worst kind of outcome: the write succeeded, the tool reported
success, and nothing appeared. Somebody spends an afternoon on it.

### So this is a resident-hand operation

ALE's `PerformIngameSpawn(spawnType, entry, mapId, instanceId, x, y, z, o)` runs
**inside** the worldserver and produces a creature immediately, visible to
everyone standing there. The deployment's own ambush system already uses exactly
this call, which makes it proven rather than proposed.

| Hand | Can it? | Why |
|------|---------|-----|
| live | no | `.npc add` needs a caller with a position |
| cold | writes a row | appears on the next grid load, which may be never |
| **resident** | **yes** | runs in-process; the creature is there when the call returns |

Hand preference is therefore `{ resident, cold }` — resident because it works
now, cold as the form that survives the world being down and is honest about
appearing later.

### Ground height is not optional

A creature spawned at the wrong Z either falls, stands inside the terrain, or
hangs in the air. The map's height at the target position has to be read, which
the resident hand can do and the cold hand cannot.

### What makes a sequence a sequence

The MVP request wants several of these, progressing. That is composition and
belongs to the model, not to this word: it calls `world.creatures` for each level
band and this word for each position. **No encounter-generator operation should
exist.** The moment one does, the model is choosing between a vocabulary and a
feature, and features are how a closed set stops being closed.

What this word owes the composition is a plan that reads as a sequence — twenty
steps, one line each, saying what appears where — so a person can read the whole
encounter before agreeing to it once rather than twenty times.

## Suggested Implementation Steps

1. Write the resident form first, since it is the one that works. A script
   installed through the resident mechanism that calls `PerformIngameSpawn`.
2. Read the ground height at the target and place on it, refusing when the
   position has no ground rather than dropping a creature into the sea.
3. Write the cold form as an `INSERT` into `creature`, and have its plan line
   say plainly that the creature appears on the next grid load. A step whose
   description hides that is a step that lies.
4. Record the spawned guid in the receipt, so the placement is reversible — a
   spawn with no receipt is a monster nobody can un-summon.
5. Test one, then twenty, then twenty across a level range.

## Open Questions

- **How is a spawn removed?** `character.retire` removes characters across
  thirty-nine tables. A creature is different rows and probably a different
  word, and without it every test of this leaves litter in the world.
- **Does a resident spawn survive a restart?** `PerformIngameSpawn` takes a save
  flag. Saved means it is in the database and permanent; unsaved means the
  encounter evaporates when the server bounces. Both are wanted, at different
  times, and the choice belongs in the declaration rather than in a constant.
- **What is a good spacing for "successive"?** Far enough apart to be separate
  fights and close enough to be one journey, which is a number nobody has looked
  at yet and belongs in `docs/balance-updates.md` once somebody has.
- **Should the creatures be hostile?** A spawned undead of the player's own
  faction stands there peacefully, which is a strange encounter.

## Related

- Issue 108 — `world.creatures`, which supplies the entry
- Issue 700 — the resident mechanism this rides
- `docs/vocabulary.txt` — the Construction section
