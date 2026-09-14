# Reading Order

Source files carry one ascending index across the whole project, so reading them
in numeric order tells the story of how a sentence becomes a change in a world.
The highest index in use is recorded in `.file-index-counter` at the project
root; a new file takes the next one.

The numbers are reading order, not creation order. A file written later may sit
earlier in the count if that is where it belongs in the telling.

A group directory takes an index of its own, so the first file inside it carries
the next one up: `src/025-enums/` is 025 and `026-enum.lua` is the first thing in
it. `tests/banners.test.lua` states that as a property, because the seven enum
files once said one number in their names and the number below it in their
header comments.

## The count so far

The table below is **generated** from the source headers by
`scripts/reading-order`, which reads each file's index off the front of its name
and its description out of its own opening sentence. To change a line here,
change the sentence at the top of the file it describes, then run the script
again. `scripts/reading-order --check` says whether this document is current
without altering it.

<!-- begin generated: the count so far -->

| Index | File | What it adds to the story |
|-------|------|---------------------------|
| 000 | `src/000-deployment.lua` | Resolves "which world" into a table of concrete facts: absolute paths, the three database names, and the credentials for both hands. |
| 001 | `src/001-json.lua` | Encode and decode JSON. |
| 002 | `src/002-cold-hand.lua` | Runs SQL against the deployment's own MySQL, over the deployment's own unix socket, using the deployment's own client binary. |
| 003 | `src/003-live-hand.lua` | Sends one GM command to a RUNNING worldserver and returns what the console printed back. |
| 004 | `src/004-liveness.lua` | Combines the two hands' probes into one answer about what may run right now, and holds the guard that prevents this project's most damaging mistake. |
| 005 | `src/005-world-read.lua` | Turns database rows into the small number of record types the rest of the project talks about. |
| 006 | `src/006-receipts.lua` | The append-only record of what was done. Every apply produces one. |
| 010 | `src/010-status-board.lua` | The observable half of phase 1: point neuron at a world and have it say what it can see and what it may therefore do. |
| 011 | `src/011-place-book.lua` | Places have names. `ratchet`, `menethil-harbor`, `the-ridge`. |
| 012 | `src/012-rosters.lua` | A roster is a named set of characters, resolved at the moment it is used. |
| 013 | `src/013-teleport.lua` | Move a roster to a place. |
| 014 | `src/014-return.lua` | Put them back. Reads a receipt, builds the inverse steps from the values it captured before overwriting, and applies them. |
| 015 | `src/015-retire.lua` | Remove characters, and every row that refers to them. |
| 016 | `src/016-dangling.lua` | Find rows that refer to a character who does not exist. |
| 017 | `src/017-creature-types.lua` | What kind of thing a creature is, and how dangerous, as two enums. |
| 018 | `src/018-bestiary.lua` | `world.creatures` -- what kinds of thing can be in the world, and which of them suit a given level. |
| 019 | `src/019-vocabulary.lua` | The closed set of words neuron knows, and the renderer that prints it as an eighty-column table. |
| 020 | `src/020-cli.lua` | The command line. One subcommand per thing a person can ask for. |
| 024 | `src/024-load.lua` | Load a source file once and hand back the same value every time after. |
| 025 | `src/025-enums/` | The closed sets, as members you can compare by identity. |
| 026 | `src/025-enums/026-enum.lua` | A closed, ordered set of named members, where a member is a unique table rather than a string. |
| 027 | `src/025-enums/027-hands.lua` | The four ways of reaching the world, as an enum. |
| 028 | `src/025-enums/028-kinds.lua` | What running an operation costs. The `k` column of the vocabulary table. |
| 029 | `src/025-enums/029-refusals.lua` | The four kinds of failure, as an enum. |
| 030 | `src/025-enums/030-slots.lua` | The nineteen equipment slots, as an enum, with the numbers the game uses. |
| 031 | `src/025-enums/031-stats.lua` | The five primary attributes, as an enum, with the indices the game uses. |
| 032 | `src/025-enums/032-classes.lua` | The nine playable classes of 3.3.5a, as an enum. |
| 033 | `src/033-mechanisms/` | The hands, given one doorway. |
| 034 | `src/033-mechanisms/034-mechanism.lua` | One hand, wearing a shape all four share, plus the table that routes to them. |
| 035 | `src/033-mechanisms/035-cold.lua` | The cold hand as a mechanism: a database write through the deployment's own MySQL socket. |
| 036 | `src/033-mechanisms/036-live.lua` | The live hand as a mechanism: one game master command to a running worldserver over its SOAP console. |
| 037 | `src/033-mechanisms/037-resident.lua` | The resident hand as a mechanism: install a Lua script into the running worldserver, where it stays and keeps running on the server's tick. |
| 038 | `src/033-mechanisms/038-none.lua` | The hand that does not reach anywhere. |
| 039 | `src/039-memory/` | What a creature holds, and for how long. |
| 040 | `src/039-memory/040-relevance.lua` | How much of a creature's attention each of its memories gets right now. |
| 041 | `src/041-vision/` | Seeing, rather than querying. |
| 042 | `src/041-vision/042-camera.lua` | Where to put a camera, and how to turn a point in a picture back into a point in the world. |
| 043 | `src/041-vision/043-adjectives.lua` | The spatial words a creature can use about a thing it can see, as an enum. |
| 044 | `src/041-vision/044-regions.lua` | A thing in a picture, and how to point at a named part of it. |
| 045 | `src/045-toolbox/` | Every word in one table, and that table as a tool list. |
| 046 | `src/045-toolbox/046-types.lua` | What a parameter can be, as an enum. The `types` legend of the vocabulary table, made into something code reads. |
| 047 | `src/045-toolbox/047-registry.lua` | Every word neuron knows, in one table, keyed by name. |
| 048 | `src/045-toolbox/048-schema.lua` | The registry, rendered as a tool list a model can be handed. |
| 049 | `src/049-spawn.lua` | `world.spawn` -- put creatures in the world. |
| 050 | `src/050-api.lua` | One HTTPS request to a model, and the answer back. |
| 051 | `src/051-loop.lua` | A sentence in, a plan or an answer out. |
| 052 | `src/052-keys.lua` | A credential is a key. |
| 054 | `src/054-stubs.lua` | A path that works and is not the thing, and says so every time it is used. |
| 055 | `src/055-list-stubs.lua` | Print every placeholder declared anywhere in the project. |
| 056 | `src/056-dialects.lua` | Two ways of saying the same conversation, and the translation between them. |
| 057 | `src/057-http.lua` | Reading a request and writing a response. The plumbing under every page neuron serves. |
| 058 | `src/058-services.lua` | The programs this world is made of: whether each is running, and how to start it. |
| 059 | `src/059-menu.lua` | The front door. One page, one level above everything else. |
| 060 | `src/060-menu-main.lua` | Start the menu. Reached through scripts/neuron-menu. |
| 061 | `src/061-broadcast.lua` | `world.announce` -- say something to everybody logged in. |
| 062 | `src/062-asking-levers.lua` | The levers for configuring where neuron sends its thinking. |
| 063 | `src/063-setup.lua` | The questions asked when there is no local model to ask them for you. |
| 064 | `src/064-source-levers.lua` | Letting the local model read the project. All of it, and none of it writable. |
| 065 | `src/065-secret-levers.lua` | Credentials, as a thing that can be checked and replaced but never read. |
| 066 | `src/066-srp6.lua` | Checking a password against a game account, without asking the account for it. |
| 067 | `src/067-transcript.lua` | A conversation, as one plain text file that is also the machine's copy. |
| 068 | `src/068-conversations.lua` | Many conversations, one port, each revived from its own transcript. |
| 069 | `src/069-similarity.lua` | Which piece of text did somebody mean, when they typed it from memory? |
| 070 | `src/070-forget.lua` | `memory.forget` -- a model shortening its own conversation, while it is still having it. |
| 071 | `src/071-shelve.lua` | `character.retire` and `character.restore` -- the deleted queue. |
| 072 | `src/072-addons.lua` | Which optional modules this deployment was built with. |
| 073 | `src/073-server-config.lua` | Reading AzerothCore's own configuration files. |
| 074 | `src/074-overrides.lua` | Writing one line of `config/deployment.lua`. |
| 075 | `src/075-reading-order.lua` | The index of the whole project, read back out of the project itself. |

*Generated from the source headers by `scripts/reading-order`. To change a line in this table, change the sentence at the top of the file it describes.*

<!-- end generated -->

## Reserved and not yet written

Nothing holds a reserved index any more — the two that were held, 017 and 024,
were taken by the bestiary and the loader while the work below was still
unwritten. Reserving a number for work that has not started is a promise the
count cannot keep, so planned work takes the next free index when it arrives and
is moved into position afterwards if the telling wants it elsewhere.

| Planned | Phase |
|---------|-------|
| scatter and formation, so a roster does not arrive as a pile | 2 |
| item lists, strip to holding, equip, loadouts | 3 |

## Tests

Tests are named for what they test rather than taking an index of their own, so
they do not consume numbers in the narrative: `tests/002-cold-hand.test.lua`
tests `src/002-cold-hand.lua`.

A test named for a property rather than a file takes no index either —
`tests/banners.test.lua` checks something true of every source file at once.

Run one directly with `luajit`. Each exits non-zero on failure. `scripts/test`
runs all of them and reports a single total.
