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
| 017 | `src/017-creature-types.lua` | What kind of thing a creature is, and how dangerous. |
| 018 | `src/018-bestiary.lua` | `world.creatures` -- the first read a model can use to look. |
| 024 | `src/024-load.lua` | Load a file once, so identity survives being reached twice. |
| 025 | `src/025-enums/` | The closed sets, as members you can compare by identity. |
| 026 | `src/025-enums/026-enum.lua` | What an enum is here, and why a member is a table. |
| 027 | `src/025-enums/027-hands.lua` | cold, live, resident, none. |
| 028 | `src/025-enums/028-kinds.lua` | read, change, final -- what running a word costs. |
| 029 | `src/025-enums/029-refusals.lua` | The four kinds of no. |
| 030 | `src/025-enums/030-slots.lua` | The nineteen equipment slots. |
| 031 | `src/025-enums/031-stats.lua` | The five primary attributes. |
| 032 | `src/025-enums/032-classes.lua` | The nine classes, their ids and their colours. |
| 033 | `src/033-mechanisms/` | The hands, given one doorway. |
| 034 | `src/033-mechanisms/034-mechanism.lua` | The shape all four share, and the routing table. |
| 035 | `src/033-mechanisms/035-cold.lua` | A database write. |
| 036 | `src/033-mechanisms/036-live.lua` | One game master command. |
| 037 | `src/033-mechanisms/037-resident.lua` | A script left running inside the world. |
| 038 | `src/033-mechanisms/038-none.lua` | No reach at all, on purpose. |
| 039 | `src/039-memory/` | What a creature holds, and for how long. |
| 040 | `src/039-memory/040-relevance.lua` | Which of its memories it is attending to right now. |
| 041 | `src/041-vision/` | Seeing, rather than querying. |
| 042 | `src/041-vision/042-camera.lua` | Where to stand to look at something, and what a pixel means. |
| 043 | `src/041-vision/043-adjectives.lua` | The spatial words, and which of them cost a raycast. |
| 044 | `src/041-vision/044-regions.lua` | A thing in a picture, and pointing at a named part of it. |
| 045 | `src/045-toolbox/` | Every word in one table, and that table as a tool list. |
| 046 | `src/045-toolbox/046-types.lua` | What a parameter can be, and what it becomes to a model. |
| 047 | `src/045-toolbox/047-registry.lua` | The closed set, keyed by name, refusing half-declared words. |
| 048 | `src/045-toolbox/048-schema.lua` | The registry as JSON Schema, and a tool call routed back. |
| 049 | `src/049-spawn.lua` | `world.spawn` -- the first word that creates anything. |
| 050 | `src/050-api.lua` | One HTTPS request to a model, through curl. |
| 051 | `src/051-loop.lua` | A sentence in, a plan out. The last piece of the pipeline. |
| 019 | `src/019-vocabulary.lua` | The closed set as declarations, and the renderer that prints it. |
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
