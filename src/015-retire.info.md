# 015-retire.lua

Remove characters and every row that refers to them. **The only operation in the
project that cannot be undone.**

## Functions

### `Retire.declaration`
Carries `reversible = false` as **data**, not as a comment, so the command line —
and in phase 8 the tool schema — can gate on it.

### `Retire.plan(handle, args) -> plan | nil, why`
`args`: `roster`, `confirm`.

Refuses when the roster contains a character on a real non-bot account unless
`confirm` is set. The gap between "remove the companions" and "remove my
characters" is one roster query.

The plan is **per table, not per character** — a plan listing 25,010 characters is
not reviewable. Exact counts are fetched only for the four statements keyed on
something other than the character's own guid, because those are the only ones
that can surprise, and surprise is what a plan is for.

A count that comes back missing is a **refusal**, not an omission. An earlier
version silently skipped counts it failed to fetch and printed a deletion whose
reach it had not measured.

### `Retire.backup(handle) -> path, size | nil, why`
Dumps the characters database before anything is removed. Part of the operation,
not a thing to remember; a failed backup refuses the whole run.

Uses `--skip-lock-tables`, not `--single-transaction`: the latter issues
`FLUSH TABLES`, which needs a privilege the deployment's user lacks. Skipping
locks is safe **because** this operation already refuses to run while the
worldserver is up, so nothing else is writing.

The dump goes to the RAM tier and **will not survive a reboot**.

### `Retire.apply(handle, plan, state) -> receipt`
Backup, then the whole deletion as one transaction. Records the removed guids —
an exact answer to "what did I remove", not enough to bring anyone back.

### `Retire.DELETIONS`
The 39 table/key pairs, transcribed from AzerothCore's `Player::DeleteFromDB`.
Read by `016-dangling.lua` rather than copied, so the removal and the check for
incomplete removal cannot drift apart.

## "Completely" is defined by the game

Four statements are keyed on something other than the character's own guid, and
they are the ones a hand-written version always forgets:

| Table | Key | Reaches |
|-------|-----|---------|
| `mail` | `receiver` | Mail addressed to them |
| `gm_ticket` | `playerGuid` | Open tickets |
| `item_instance` | `owner_guid` | The item rows, not just the inventory slots |
| `character_social` | `friend` | Their presence in **other people's** friend lists |

## Why one script, not one statement at a time

A transaction cannot span connections, and the rest of the cold hand is one
connection per statement. 25,010 characters at 39 statements each would also be
975,000 subprocesses.

Both are solved the same way: the guid list goes into a temporary table once,
each deletion refers to it by subquery, and the whole job is one script in one
connection. 39 statements. It runs in about 45 seconds.
