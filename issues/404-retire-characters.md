# 404 — `character.retire`: Remove Characters Completely

## Status
- Phase: 4 (Company)
- Blocked by: 102 (cold hand), 105 (reading the world), 202 (rosters)
- **Not reversible.** The only operation in the project that is not.

## Current Behavior

Nothing exists. Characters are removed by deleting their account and leaving
their rows behind, which is how the live deployment came to hold 900 characters
that belong to nobody, cannot be logged in, and are invisible to any query that
joins accounts with an inner join.

That residue is the evidence for this ticket. Removing a character halfway is
worse than not removing it, because the half that remains is the half nobody
looks at.

## Intended Behavior

Remove a roster of characters and every row that refers to them.

### "Completely" is defined by the game, not by us

AzerothCore's own `Player::DeleteFromDB` is the authority. In its
`CHAR_DELETE_REMOVE` mode it issues **39 statements inside a single
transaction**. Copying that list is what makes this operation idiomatic;
inventing a table list is how you produce the next 900 orphans.

Four of those statements are keyed on something **other** than the character's
own guid, and they are the ones a hand-written version always forgets:

| Statement | Keyed on | Why it matters |
|-----------|----------|----------------|
| `DELETE FROM character_social WHERE friend = ?` | `friend` | Removes them from **other people's** friend lists |
| `DELETE FROM mail WHERE receiver = ?` | `receiver` | Mail addressed to them |
| `DELETE FROM item_instance WHERE owner_guid = ?` | `owner_guid` | The item rows themselves, not just the inventory slots |
| `DELETE FROM gm_ticket WHERE playerGuid = ?` | `playerGuid` | Open tickets |

The core also does work that is not SQL at all — removing from guilds, arena
teams, groups, and petitions, and **returning cash-on-delivery mail to its
senders** before dropping it. For an offline character with no worldserver
running, the in-memory half cannot happen, so the equivalent must be done as SQL
or consciously skipped. Skipping is acceptable for generated companions that
were never in a guild; it is not acceptable for a person's character.

### One transaction, not one per character

The core wraps its 39 statements in a transaction so a character is never half
deleted. This operation must do the same, and that constraint collides with the
cold hand's shape: it runs one statement per subprocess, so each statement is its
own connection and a transaction cannot span them.

Deleting 25,010 characters at 39 statements each would also be 975,000
subprocesses, which is not a performance problem so much as a physical
impossibility.

Both are solved the same way. The whole job goes to the database as **one script
in one connection**:

1. `CREATE TEMPORARY TABLE` holding the guids to remove.
2. Populate it.
3. `START TRANSACTION`.
4. The 39 deletions, each as `DELETE ... WHERE <key> IN (SELECT guid FROM <temp>)`.
5. `COMMIT`.

Thirty-nine statements total rather than per character, one connection, one
transaction, and the temporary table disappears with the connection whether the
script succeeded or not. The cold hand grows a `script` function for this, and it
is the right primitive for any future set-shaped work.

### It cannot be undone, and must say so

Every other operation captures prior values so a receipt can reverse it. This one
cannot: restoring a character needs every row from all 39 tables, and a receipt
holding that for 25,010 characters is a database, not a record.

So `reversible = false`, the plan says so in as many words, and the receipt
records **what was removed** — counts per table and the guid list — without
pretending that is enough to bring anyone back.

A dump taken before the deletion is the actual safety net, and taking one is part
of the operation rather than a thing to remember.

### The plan is per table, not per character

A plan listing 25,010 characters is not reviewable. The plan for this operation
reports **how many rows would go from each of the 39 tables**, which is both
readable and the thing that would reveal a mistake — an unexpected count against
`character_social` means the roster caught somebody's friend.

## Suggested Implementation Steps

1. Add `ColdHand.script` — many statements, one connection, one transaction.
   Everything else in the project is single-statement; this is the exception and
   should look like one.
2. Transcribe the 39 statements from the core's own deletion routine, keeping the
   source's ordering, and note beside each of the four non-guid-keyed ones what
   it is actually reaching.
3. Write the plan: resolve the roster, count the rows each statement would remove,
   and report per table.
4. Refuse, loudly, if the roster contains a character on a real non-bot account,
   unless that is explicitly confirmed. The gap between "delete the companions"
   and "delete my characters" is one roster query.
5. Take a dump before applying, and record its path in the receipt.
6. Apply the script; record counts.
7. Verify afterwards by re-running the summary — the orphan count is the number
   that proves the job was complete.

## Open Questions

- **What about the accounts?** Deleting a bot's character leaves its RNDBOT
  account behind. Whether the accounts should go too depends on whether
  mod-playerbots reuses them when it regenerates its fleet. If it does, deleting
  them is destructive; if it does not, leaving them is the next kind of residue.
- **Should retiring a person's character be allowed at all?** It is the same
  operation and a much worse mistake. A confirmation flag is the current answer
  and may be too weak.
- **Does the fleet regenerate identically?** mod-playerbots creates its fleet
  from configuration on startup, so the count returns but the characters are new
  — new guids, names, and gear. Anyone attached to a particular companion should
  know that before this runs.

## Related

- `Player::DeleteFromDB` in the deployment's AzerothCore source — the authority
- Issue 105 — where the 900 orphans were found
- Issue 202 — the roster this acts on
