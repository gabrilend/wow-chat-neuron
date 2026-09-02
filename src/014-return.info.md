# 014-return.lua

Put them back. Reads a receipt, builds the inverse from the values captured
before overwriting, applies them.

## Functions

### `Return.declaration`
### `Return.plan(handle, args) -> plan | nil, why`
`args.receipt` is the id. Searches every dated log, newest first — undoing
something the next morning is the common case.
### `Return.describe_plan(plan) -> string`
### `Return.apply(handle, plan, state) -> receipt`
Delegates to `Teleport.apply`. The inverse is an ordinary plan and goes through
ordinary machinery rather than a parallel path that would need keeping in step.

## It is a second operation, not a rollback

An apply that fails stops and leaves a partial change; it does not unwind itself.
Unwinding needs the same guards and liveness as going forward, and a failed
rollback inside a failed apply is worse than a half-changed world with an exact
record of itself.

So reversal is deliberate: it plans, it can be dry-run, it is guarded, and it
writes a receipt of its own — an undo can itself be undone.

## Keyed by GUID, never by name

A character can be renamed, and a freed name can be taken by somebody else.
Restoring "the character now called Aalaan" rather than "the character that was
moved" is how the wrong person ends up somewhere.

## Only steps that actually changed something

| Step outcome | Reversed | Why |
|--------------|----------|-----|
| `done` with restores | yes | It changed something and we know what |
| `rerouted` | yes | Same, by the other hand |
| `done` without restores | no | A live-hand step captured nothing |
| `failed` / `refused` / `skipped` | no | Nothing changed |

Reversing a step that never ran would move a character who was never moved.

## Drift is reported, not refused

Each character's current position is compared against what the receipt says the
original step **wrote** — not against what it overwrote. Differing from the prior
position is what a successful change means; differing from the written position
is drift.

Coordinates compare with a half-yard tolerance, because the columns are 4-byte
floats and the values passed through Lua doubles: an exact comparison reports
every untouched character as drifted.

## A receipt from another profile is refused

Not warned about. Restoring characters using coordinates recorded in a different
world is a catastrophe that would look, from outside, like the tool working.
