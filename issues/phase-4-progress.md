# Phase 4 — Company: Progress

**Effect: nobody is alone, and a group outlives its members.**

## Where it stands

| Issue | Title | Status |
|-------|-------|--------|
| 401 | Reading groups | Done (the reader landed with phase 1) |
| 402 | `party.assemble` | Not started |
| 403 | Bot generation | Not started |
| 404 | `character.retire` | Done, run against the live deployment |
| 405 | The garrison | Not started — needs the resident hand |
| 406 | Garrison persistence | Not started |
| 407 | Guards fan out and take the high ground | Not started |

404 arrived out of order because the world needed clearing before anything else
was worth building on it.

## What was removed

25,010 characters: the entire 24,110-strong companion fleet and the 900
characters that belonged to nobody. Five remain, all on the one real account.
`neuron check` reports no dangling rows across 39 table/column pairs.

The fleet regenerates on the next worldserver start according to
mod-playerbots' population configuration — as **new** characters, with new
identities and gear, not the ones that were there.

## The journey

**"Idiomatically" turned out to have a precise answer, and it was not ours.**
AzerothCore's own `Player::DeleteFromDB`, in its complete-removal mode, issues
39 statements inside one transaction. Transcribing that list is what makes the
operation correct; inventing a table list is exactly how the 900 orphans came to
exist in the first place.

Four of those statements are keyed on something other than the character's own
identifier, and they are the ones a hand-written version always misses:
mail *addressed to* them, open tickets, the item rows themselves rather than the
inventory slots pointing at them, and — the one worth naming — their presence in
**other people's friend lists**. The plan reports those four exactly and the rest
by roster size, because those four are the only ones that can surprise, and
surprise is the entire purpose of a plan. On the real run they read 0, 0,
459,850, and 0: nearly half a million item rows that would otherwise have been
left pointing at nobody, and no real player's friend list touched.

**A transaction cannot span connections, and that reshaped the cold hand.**
Everything in this project had been one statement per subprocess, which is fine
for single writes and fails two ways here: a transaction needs one session, and
25,010 characters at 39 statements each is 975,000 subprocesses, which is not
slow so much as impossible.

Both wants the same answer. The guid list goes into a temporary table once, each
deletion refers to it by subquery, and the whole job is one script in one
connection — 39 statements instead of 975,000. The cold hand grew a `script`
function for it, and that is now the right primitive for any set-shaped work.
The run took 45 seconds.

**A silent failure, caught by scale.** The plan's exact counts worked for 900
characters and vanished for 24,110 — because a guid list that long makes the
count statement exceed the command line it is passed on, the read returned
nothing, and the code skipped it with a nil check. The plan printed a deletion
whose reach it had failed to measure and said nothing about it. Counting now
goes through the same temporary table, and a count that comes back missing is a
refusal rather than an omission: describing a deletion whose reach is unknown is
worse than refusing to describe it.

**Two failures that were the safety net working.** The first real attempt
refused, because the backup failed. The backup failed because `--single-transaction`
makes this client issue `FLUSH TABLES`, and the deployment's database user does
not hold the privilege that needs. And the error said only "mysqldump failed",
which is a message that tells the reader nothing they did not know, because
stderr had been discarded.

Both fixed. The dump skips locking instead, which is safe here for a reason worth
recording: this operation already refuses to run while the worldserver is up, so
nothing else is writing while the dump is taken. A guard written for one purpose
— not deleting rows out from under a live server — turned out to also make an
unlocked dump consistent.

**A flag that did not exist.** The script primitive originally passed
`--abort-source-on-error` to stop at the first failing statement. This client is
version 9.6.0 and has no such option, so the flag itself became the error. It
turned out to be unnecessary: batch mode already stops at the first failure and
exits non-zero, verified by feeding it a script with a bad statement in the
middle and confirming the statements after it never ran. Since the failure comes
before `COMMIT`, a script that dies partway changes nothing at all.

**The check exists because the residue did.** `neuron check` looks for rows that
name a character who does not exist, over the same table list the removal uses —
read from that module rather than copied, so the two cannot drift. It is the only
thing that can prove a removal was complete, and it is the alarm for the next one
that is not. It exits non-zero when it finds anything, on the standing position
that a warning is an error.

## Backups

Two dumps were taken, one before each removal, into `/dev/shm/wow-chat-neuron/`.
That is RAM. **They will not survive a reboot.** Copying one somewhere durable is
a deliberate act nobody has performed yet.

## Open questions carried forward

From issue 404: whether the RNDBOT **accounts** should be removed too. 2,210 of
them remain with no characters. If mod-playerbots reuses them when regenerating
its fleet, removing them is destructive; if it creates fresh ones, leaving them
is the next kind of residue. This is unanswered and is the direct sequel to the
question this phase just settled.

Also from 404: whether a confirmation flag is strong enough protection for an
operation with no reverse, given the gap between "remove the companions" and
"remove my characters" is one roster query.
