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
| 001 | `src/001-json.lua` | Encode and decode, for receipts and the API. |
| 002 | `src/002-cold-hand.lua` | SQL over the deployment's own socket. The hand that works when the world is down. |
| 003 | `src/003-live-hand.lua` | GM commands over the SOAP console. The hand that works when it is up. |
| 004 | `src/004-liveness.lua` | Which hands are usable right now — and the guard against writing to a logged-in character. |
| 005 | `src/005-world-read.lua` | Rows become records. Nothing above this writes a SELECT. |
| 006 | `src/006-receipts.lua` | The append-only record of what was done, and what it overwrote. |
| 010 | `src/010-status-board.lua` | Point at a world and say what you can see. |
| 011 | `src/011-place-book.lua` | Places have names. Mostly the game's own, some ours. |
| 012 | `src/012-rosters.lua` | Who to act on: a name, a list, or a description. |
| 013 | `src/013-teleport.lua` | The first operation that changes the world. |
| 014 | `src/014-return.lua` | Putting it back, from the receipt. |
| 015 | `src/015-retire.lua` | Removing characters completely. The one thing with no reverse. |
| 016 | `src/016-dangling.lua` | Proving a removal was complete, and catching one that was not. |
| 020 | `src/020-cli.lua` | The command line, so a person can pull the levers with no model involved. |
| 021 | `src/021-chat-router.lua` | A sentence becomes an operation. The substrate a model will write to. |
| 022 | `src/022-http-server.lua` | Three routes, so the window has something to talk to. |
| 023 | `src/023-chat-main.lua` | Starting the window. |

## Reserved and not yet written

| Index | Planned | Phase |
|-------|---------|-------|
| 017+ | scatter and formation, so a roster does not arrive as a pile | 2 |
| 024+ | item lists, strip to holding, equip, loadouts | 3 |

## Tests

Tests are named for what they test rather than taking an index of their own, so
they do not consume numbers in the narrative: `tests/002-cold-hand.test.lua`
tests `src/002-cold-hand.lua`.

Run one directly with `luajit`. Each exits non-zero on failure.
