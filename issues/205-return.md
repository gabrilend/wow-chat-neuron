# 205 — `character.return`

## Status
- Phase: 2 (Displacement)
- Blocked by: 106 (receipts), 203 (teleport)

## Current Behavior

A teleport writes a receipt holding every moved character's prior map,
coordinates, and facing. Nothing reads it back, so a move is a one-way door.

## Intended Behavior

Put them back.

```
neuron receipts                                   # find the one
neuron return --receipt 20260901T234430-7ca8d3 --plan
neuron return --receipt 20260901T234430-7ca8d3
```

Reads a receipt, builds the inverse steps from its `restores` values, and
applies them.

### It is a second operation, not a rollback

An apply that fails stops and leaves a partial change. It does **not** unwind
itself, because unwinding needs the same guards and the same liveness as going
forward, and a failed rollback inside a failed apply is a worse place to be than
a half-changed world with an exact record of itself.

So reversal is deliberate: a person reads the receipt, decides, and runs a
separate operation that is guarded exactly like any other. It plans, it can be
dry-run, and it writes a receipt of its own — which means an undo can itself be
undone.

### Keyed by GUID, never by name

A receipt records both, and the reversal uses the **GUID**. A character can be
renamed, and a name freed by a rename can be taken by somebody else. Restoring
"the character now called Aalaan" rather than "the character that was moved" is
how the wrong person ends up somewhere.

### Only steps that actually changed something

A receipt's steps carry outcomes. Reversal considers only `done` and `rerouted`
steps that hold `restores` values:

| Step outcome | Reversed? | Why |
|--------------|-----------|-----|
| `done` with restores | yes | It changed something and we know what |
| `rerouted` | yes | Same, by the other hand |
| `done` without restores | no | A live-hand step; nothing was captured |
| `failed`, `refused`, `skipped` | no | Nothing changed, so nothing to undo |

That last row matters: reversing a step that never ran would move a character
who was never moved.

### Drift is reported, not ignored

A character may have moved again since the receipt was written — by another
operation, or by playing. Restoring them to where a stale receipt says they were
is technically correct and possibly not what anyone wants.

So the plan compares each character's **current** position against what the
receipt expected to have left them at, and reports any that differ. It does not
refuse; it says so, and lets the person decide.

## Suggested Implementation Steps

1. Write the receipt lookup by id, across dated log files rather than only
   today's — an undo the next morning is the common case.
2. Write the inverse plan: for each reversible step, one cold step restoring the
   captured fields, subject keyed by GUID.
3. Read every subject's current position in one query and mark the drifted ones.
4. Reuse teleport's apply, which already guards, captures priors, and writes a
   receipt. The inverse is an ordinary plan and should go through ordinary
   machinery, not a parallel path.
5. Add the `return` subcommand with `--plan`.
6. Test: move characters, return them, and confirm the positions match the
   originals exactly — including map, which is the field whose absence looks
   like the teleport silently failing.

## Open Questions

- **How long is a receipt useful?** A move can be undone an hour later. A week
  later, after the character has moved twenty times, restoring is strange but
  well-defined. Drift reporting is the current answer; a hard expiry might be
  better and would need a number nobody has a basis for yet.
- **Should reversing a partial receipt be allowed?** It is exactly the case
  where reversal is most wanted, and exactly the case where the world is least
  understood. Currently allowed, because refusing would leave somebody with a
  half-changed world and no tool.
- **What about a receipt from another profile?** Receipts record the profile.
  Restoring characters using coordinates from a different world is a
  catastrophe, and the check for it should be a refusal rather than a warning.

## Related

- Issue 106 — receipts, and why `restores` exists at all
- Issue 203 — teleport, whose receipts this reads
- `docs/datapath-operation-dispatch.md` — step 7, and why apply does not unwind
