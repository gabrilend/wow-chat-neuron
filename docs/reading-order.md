# Reading Order

Source files carry one ascending index across the whole project, so reading them
in numeric order tells the story of how a sentence becomes a change in a world.
The highest index in use is recorded in `.file-index-counter` at the project
root; a new file takes the next one.

The numbers are reading order, not creation order. A file written later may sit
earlier in the count if that is where it belongs in the telling.

## The count so far

| Index | File | What it adds to the story |
|-------|------|---------------------------|
| 000 | `src/000-deployment.lua` | Which world, and how to reach it. Everything below takes this handle as its first argument. |
| 002 | `src/002-cold-hand.lua` | SQL over the deployment's own socket. The hand that works when the world is down. |
| 003 | `src/003-live-hand.lua` | GM commands over the SOAP console. The hand that works when it is up. |
| 004 | `src/004-liveness.lua` | Which hands are usable right now — and the guard against writing to a logged-in character. |
| 005 | `src/005-world-read.lua` | Rows become records. Nothing above this writes a SELECT. |
| 010 | `src/010-status-board.lua` | The observable half of phase 1: point at a world and say what you can see. |

## Reserved and not yet written

| Index | Planned | Phase |
|-------|---------|-------|
| 001 | `src/001-json.lua` — encode and decode, for receipts and the API | 1 |
| 006 | `src/006-receipts.lua` — the append-only record of what was done | 1 |
| 011+ | the place book, rosters, and displacement | 2 |

001 is reserved rather than used because JSON belongs before the hands in the
telling — receipts and the API both need it — and it has not been written yet.
Leaving the hole is better than renumbering five files later.

## Tests

Tests are named for what they test rather than taking an index of their own, so
they do not consume numbers in the narrative: `tests/002-cold-hand.test.lua`
tests `src/002-cold-hand.lua`.

Run one directly with `luajit`. Each exits non-zero on failure.
