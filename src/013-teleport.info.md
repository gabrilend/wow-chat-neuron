# 013-teleport.lua

Move a roster to a place. The first operation that changes the world, and the
right first one: it is the simplest thing that still needs both hands.

## Functions

### `Teleport.declaration`
Name, summary, hand preference (`live` then `cold`), reversibility, and typed
parameters. One declaration serves the command line and — in phase 8 — the tool
schema handed to a model, so an operation cannot exist as a command without
existing as a tool.

### `Teleport.plan(handle, args) -> plan | nil, why`
`args`: `roster`, `place`, optional `limit`, `include_orphans`.

Pure. Reads freely, writes nothing. Returns the destination, the roster
resolution, and one step per character.

### `Teleport.describe_plan(plan) -> string`
The operation's real interface — read far more often than the code, and shown as
a model's proposal before anything happens. Warns when the destination is inside
an instance.

### `Teleport.apply(handle, plan, state) -> receipt`
Walks the steps. A failing step **stops the run**; the rest are recorded as
skipped. There is no automatic rollback — see `docs/datapath-operation-dispatch.md`.

Also used by `014-return.lua`, so the inverse goes through the same guarding,
prior-value capture, and receipt writing rather than a parallel path.

## The hand is chosen per character

| The character is | Hand | Why |
|------------------|------|-----|
| offline | cold | Nothing holds their state; the row **is** their position |
| online | live | A row write is overwritten by the server's next save |

The live hand cannot help an offline character at all — a game master teleport
needs a character present in the world.

An **online** character sent to a **project** place is refused: `tele name` only
accepts locations the game itself knows.

## What is written, and what is not

Written: `map`, `position_x`, `position_y`, `position_z`, `orientation`, plus a
`wrote` record for drift detection later.

**Not written: `zone`.** The server recomputes it from the position at login. A
stale zone beside a fresh position produces a character who is in Ratchet and
believes they are in Menethil.

**The map is not optional.** Coordinates without it put a character at the right
numbers on the wrong continent, which looks like the teleport doing nothing.

## Zero affected rows is not an error

A successful write affecting no rows means the character was already exactly
there. Recorded as done, with that as the evidence.
