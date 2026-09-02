# 006-receipts.lua

The append-only record of what was done. Every apply produces one.

A receipt is not a log line for somebody skimming a terminal — it is the input to
three other features, and its shape is set by what they need: reversal needs
prior values, renewal history needs what a character was, narration needs what
happened in describable terms.

## Functions

### `Receipts.begin(handle, operation, arguments) -> receipt`
Starts one. Filled in **progressively** by apply rather than assembled at the
end: a run that dies partway must still leave a record of the steps that
finished, and a receipt built only on success is missing exactly when it matters.

Records the **profile**, so a receipt from the wrong world is unmistakable.
Restoring characters using another world's coordinates is worse than not
restoring them.

### `Receipts.record(receipt, step, outcome, restores, evidence)`
Adds one step. Outcomes: `done`, `failed`, `refused`, `skipped`, `rerouted`.

`restores` is the columns as they were **before**. `step.wrote` — what the step
put there — is captured alongside it. Both are needed: knowing only the prior
value, an undo cannot tell "untouched since" from "moved twice", because
differing from the prior position is what a successful change means.

### `Receipts.finish(receipt, outcome) -> receipt`
Outcome is **derived from the steps** unless forced, so it cannot disagree with
them. `refused` = nothing ran; `complete` = everything ran and succeeded;
`partial` = the world is half-changed, which is the word that matters.

### `Receipts.append(handle, receipt) -> path | nil, why`
One JSON object per line, **flushed immediately**. An unflushed receipt for a
step that already changed the world is worse than none: the world moved and the
record did not.

Returns nil on failure rather than swallowing it — the operation may already have
changed things, and losing that record is the one failure this module exists to
prevent.

### `Receipts.read(handle, filter) -> receipts, unreadable`
`filter` may carry `operation`, `date`, `guid`. A line that will not parse is
skipped and **counted**: a process killed mid-write leaves a truncated final
line, and refusing to read nine hundred good receipts because of it is the wrong
trade.

### `Receipts.describe(receipt) -> string`

## Where they live

`tmp/shared-memory/receipts/<date>.log` — the RAM-backed tier. It does not
survive a reboot, so a missing directory is a **normal** state and anything
writing must create it. Whether receipts should be rotated somewhere permanent is
open question 3 in `docs/architecture.md`.
