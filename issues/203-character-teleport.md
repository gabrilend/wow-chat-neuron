# 203 — `character.teleport`

## Status
- Phase: 2 (Displacement)
- Blocked by: 201 (place book), 202 (rosters), 106 (receipts), 104 (liveness guard)
- Blocks: 205 (return)

## Current Behavior

Nothing exists. Moving a character means editing a database row by hand and
knowing which of several ways will actually stick.

## Intended Behavior

Move a roster to a place.

```
neuron teleport --roster my-party --place ratchet --plan
neuron teleport --roster my-party --place ratchet
```

This is the operation the project was asked for first, and it is the right first
one because it is the simplest thing that still needs **both hands** and
therefore proves the whole model.

### One name, two hands, chosen per character

The hand is not chosen for the operation. It is chosen **per character**,
because the right answer differs between two characters in the same roster:

| The character is | Hand | Why |
|------------------|------|-----|
| offline | cold | Nothing holds their state; the row IS their position |
| online | live | A row write would be overwritten by the server's next save |

An offline character teleported by database write appears at the destination
when they next log in. An online character teleported by game master command
moves immediately, visibly, in front of everyone.

Getting this backwards is the silent failure the whole liveness guard exists to
prevent, and this operation is where it would first have happened.

### What `plan` computes

For each resolved roster member: their current position, the destination, which
hand applies, and one readable sentence. It writes nothing.

```
plan: move 4 characters to Ratchet (Kalimdor, -956.7 -3754.7 5.3)

  Grast     offline  cold  Eastern Kingdoms -3769,-744  ->  Ratchet
  Wenna     offline  cold  Kalimdor 2781,-433           ->  Ratchet
  Aalia     ONLINE   live  Kalimdor 1629,-4373          ->  Ratchet
  Borin     offline  cold  Eastern Kingdoms -5,-942     ->  Ratchet
```

The `plan` output is the thing a person reads before forty characters move, and
it is the same thing shown when a model proposes the operation.

### What `apply` does

Walks the steps. Before each cold step, the liveness guard re-checks that
character's online state, because the minutes between planning and approving are
minutes in which somebody can log in. A character who logged in between the two
is **rerouted** to the live hand, not written and hoped for.

Before each write, the character's current position is captured into the
receipt. That capture is what makes issue 205 possible: forty characters can be
put back because the receipt knows where all forty were.

### Position is four numbers and a map, not three

`map`, `position_x`, `position_y`, `position_z`, `orientation`. Writing the
three coordinates without the map produces a character at the right numbers on
the wrong continent, which is a shape of bug that looks like the teleport
silently doing nothing.

`zone` is also stored on the character row and is **not** written. The server
recomputes it from the position on login. Writing a stale zone alongside a fresh
position is how you get a character who is in Ratchet and thinks they are in
Menethil.

## Suggested Implementation Steps

1. Write `plan`: resolve the roster, resolve the place, read every member's
   current position in one query, decide a hand per member, build one step each.
2. Write the readable step description. It is the operation's actual interface;
   a person will read it far more often than they read the code.
3. Write `apply`: guard, capture prior position, execute, record.
4. Write the cold step as a single parameterised UPDATE per character. Do **not**
   batch into one statement with a CASE — the receipt needs a per-character
   outcome, and a batched write cannot say which of forty failed.
5. Write the live step as `tele name <character> <place>`, which requires the
   place to be one the game knows. A project-only place must use the coordinate
   form instead.
6. Write `--plan` as the dispatcher flag that stops after step 5 of the datapath.
7. Test against real characters: one offline, one online, one that does not
   exist, one that is an orphan.

## Open Questions

- **What if the destination is an instance map?** Writing an offline character
  into one may produce a character who cannot log in. Needs a guard that knows
  which maps are instances.
- **Should everyone land on the same spot?** Forty characters on one coordinate
  is a stack. Issue 204 is the scatter, and until it exists this operation
  produces a pile.
- **What about a character who is dead?** A corpse is at a different position
  than the character. Teleporting the living body and leaving the corpse behind
  may be correct or may be cruel.
- **Should the live hand's teleport be preferred even for offline characters
  when the world is up?** It would not work — the game master command needs a
  character in the world. Confirmed, worth stating, since it is the obvious
  thing to try.

## Related

- `docs/datapath-displacement.md`
- `docs/datapath-operation-dispatch.md` — the eight steps this rides
- Issue 205 — return, which reads this operation's receipts
