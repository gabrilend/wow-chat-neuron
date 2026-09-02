# 106 — Receipts: The Append-Only Record of What Was Done

## Status
- Phase: 1 (Reach)
- Blocked by: 101 (deployment handle)
- Blocks: 205 (return), 505 (renewal receipts), 605 (world.clear), 1002 (narrating a receipt)

## Current Behavior

Nothing exists. An operation that ran leaves no trace, so nothing can be undone
and nothing can be narrated.

## Intended Behavior

Every `apply` produces a receipt. Receipts are appended to a log, one JSON
object per line, and are never edited or deleted.

The receipt is not a log line for a human skimming a terminal. It is the
**input to three other features**, and its shape is set by what they need:

- **Reversal** (issues 205, 605) needs the prior value of everything overwritten.
- **Renewal history** (issue 505) needs what a character was before.
- **Narration** (issue 1002) needs what happened in terms a voice can describe.

### Shape

| Field | Type | Meaning |
|-------|------|---------|
| `id` | string | Unique, sortable, time-prefixed |
| `operation` | string | Registered operation name |
| `arguments` | table | Resolved arguments, after coercion |
| `deployment` | string | Which deployment root |
| `profile` | string | Which profile — a receipt from the wrong profile must be unmistakable |
| `started`, `finished` | string | Wall-clock, ISO 8601 |
| `outcome` | string | `complete`, `partial`, or `refused` |
| `steps` | array | One entry per planned step |

A step entry:

| Field | Type | Meaning |
|-------|------|---------|
| `describes` | string | The human line from the plan |
| `hand` | string | `cold`, `live`, or `resident` |
| `outcome` | string | `done`, `failed`, `skipped`, `rerouted` |
| `subject` | table | `{guid, name}` when a character |
| `restores` | table | **The prior value.** Column names to previous values. |
| `evidence` | string | For live steps, the console output verbatim |

### `restores` is the reason for all of it

Before any step overwrites a value, the previous value is read and stored. That
read costs one query per write and buys the entire reversal feature. An
operation that moved forty characters can put them all back because the receipt
knows where each of them was standing.

Without it, `character.return` cannot exist, and "move everyone to the docks"
becomes a one-way door.

### Append-only, and why it is not stylistic

A receipt log that can be edited is a receipt log that cannot be trusted to
say where forty characters used to be. The append-only property is what makes
the reversal safe to run without a human verifying each line first.

The log lives under the RAM-backed shared-memory tier while running:
`tmp/shared-memory/receipts/<date>.log`. RAM does not survive a reboot, which
is fine for a working log and not fine for a permanent record — see the open
question.

### Refusals are receipts too

An operation that refused produces a receipt with `outcome: "refused"` and no
executed steps. This matters because a refusal is a fact about the world at a
moment — "these four characters were online, so I did not move them" — and the
question "why didn't that work an hour ago" deserves an answer.

## Suggested Implementation Steps

1. Write the JSON encoder. Lua has no bundled one, and the project avoids
   package managers, so it is written here — it needs only the subset covering
   the receipt shape, and it must escape strings correctly, which is the part
   worth testing against a character name with a quote in it.
2. Write the receipt constructor, populated progressively by `apply` as steps
   complete rather than assembled at the end. A run that dies partway must still
   leave a receipt for the steps that finished.
3. Write the appender: ensure the directory exists (the shared-memory tier may
   be empty after a reboot), open for append, write one line, flush. Flushing
   per line is the point — an unflushed receipt for a step that just changed the
   world is worse than no receipt.
4. Write the reader: parse a log back into receipts, filter by operation, by
   date, by subject character.
5. Write the `restores` capture helper that operations call before an
   overwriting write, so no operation writes that logic itself.
6. Write the `.info.md`.

## Open Questions

- **Where do receipts finally live?** RAM while running, but a reboot loses
  them. Rotating them into the repository makes them permanent and reviewable —
  and also makes every character move a tracked file change forever, which is
  either an excellent property or an unbearable one depending on the day.
  Open question 3 in `docs/architecture.md`.
- **How long is a receipt useful for reversal?** A move can be undone an hour
  later; can it be undone a week later, after the character has moved twenty
  times? Reversal to a stale position is technically fine and semantically
  strange. Perhaps reversal should warn when the current state no longer
  matches what the receipt expected.
- **Should receipts be signed?** The project's own writing has a standing
  interest in append-only records verified by checksum, where each entry commits
  to the one before it. That would make the log tamper-evident rather than
  merely conventionally append-only. Attractive, and not needed for phase 1.

## Related

- `docs/datapath-operation-dispatch.md` — step 8
- `notes/vision` — the standing position on append-only memory
