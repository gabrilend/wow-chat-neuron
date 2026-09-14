# Roadmap

Phases are grouped by **effect** — what becomes true once the phase lands —
rather than by the order anyone happened to build them. Lower numbers are more
foundational. A high-numbered phase assumes the low-numbered ones work; a
low-numbered issue may well be the last thing finished.

Nothing here is time-gated. A phase is done when its issues are done.

---

## Phase 1 — Reach

**Effect: the world is addressable.**

neuron can name a deployment, connect to it, tell you whether its database and
its worldserver are up, and read a fact out of it. The two hands exist and are
separately testable. Nothing is changed yet — this phase is entirely about
being able to see.

The demo for this phase is a status board: point neuron at wow-chat-2026 and
have it print what is running, which profile is active, how many characters
exist, how many are online, and which hands are currently usable.

| Issue | Title |
|-------|-------|
| 101 | Deployment handle and configuration |
| 102 | The cold hand — parameterised SQL against the deployment |
| 103 | The live hand — GM commands over the SOAP console |
| 104 | Liveness probes and the hand-availability matrix |
| 105 | Reading the world — characters, positions, online state |
| 106 | Receipts — the append-only record of what was done |
| 111 | The plain WotLK target platform (work lands in the deployment) |

---

## Phase 2 — Displacement

**Effect: anyone can be anywhere.**

Moving characters through space, one or many at a time, by name or by roster.
This is the phase that proves the operation model, because teleport is the
simplest thing that still needs both hands: an online character must be moved
by GM command, an offline one by database write, and the caller should not have
to know which.

Places are named, not typed as coordinates. A place is a row in a table the
project owns — `ratchet-dock`, `the-ridge`, `menethil-harbour` — carrying map,
coordinates, orientation, and a human description.

| Issue | Title |
|-------|-------|
| 201 | The place book — named coordinates with a map and a description |
| 202 | Rosters — named sets of characters, resolved at use time |
| 203 | `character.teleport` — move a roster to a place |
| 204 | Scatter and formation — arriving as a group, not a stack |
| 205 | Return — undo a displacement from its receipt |

---

## Phase 3 — Outfitting

**Effect: anyone can be wearing anything.**

Changing what characters own and wear. Give an item list to a roster; strip a
character to nothing; save a character's current kit as a named loadout and put
someone else in it.

The pattern to copy is already written and proven in the sibling project:
wow-chat-2026's first-login equipment hook strips every slot unconditionally
and then re-adds from a single source of truth, because checking what someone
is wearing before replacing it is more code and more bugs than not checking.

| Issue | Title |
|-------|-------|
| 301 | Item lists — named sets of item entries with counts |
| 302 | `character.strip` — empty every slot, equipped and carried |
| 303 | `character.equip` — install an item list and route it to slots |
| 304 | Loadouts — capture a character's kit, apply it to another |
| 305 | Proficiency and skill repair — make the given weapon actually equippable |

---

## Phase 4 — Company

**Effect: nobody is alone, and a group outlives its members.**

Parties, bot generation, and the garrison.

The garrison is the centrepiece and the reason this phase is not simply "party
management". When a party contains a character whose player has logged out, the
party does not dissolve. The bots hold the position, fight whatever arrives,
die, respawn, and walk back to the same spot — until the absent player returns
or the server stops. No stand-in is spawned for the missing player. The gap
where a person was stays a gap.

| Issue | Title |
|-------|-------|
| 401 | Reading groups — who is partied with whom, online or not |
| 402 | `party.assemble` — build a party from a roster, ignoring login state |
| 403 | Bot generation — create playerbot characters to specification |
| 404 | Bot retirement — remove generated bots and their rows, completely |
| 405 | The garrison — a standing watch on a coordinate (resident hand) |
| 406 | Garrison persistence — what a watch remembers across death and respawn |
| 407 | Guards fan out and take the high ground (wave search) |

---

## Phase 5 — Renewal

**Effect: a character can change without being replaced.**

Level a character up or down and re-fit them for where they landed. This is not
`.character level` — that changes a number. Renewal changes the number *and*
everything that should follow from it: gear appropriate to the new band, skills
capped correctly, spells learned or forgotten, talents redistributed.

And style. A character carries a **style vector** — an accumulated record of
what this character has tended toward, built from what it has been given and
what it has done. Renewal nudges the style rather than rerolling it, so a
companion you have played with for a month is recognisably the same character
and also not the same as it was.

| Issue | Title |
|-------|-------|
| 501 | The style vector — what it holds and how it is stored |
| 502 | `character.relevel` — move a character to a level band, coherently |
| 503 | Style-aware outfitting — pick from an item list by leaning, not at random |
| 504 | Style evolution — how a vector moves, and what moves it |
| 505 | Renewal receipts — what a character was before it was renewed |

---

## Phase 6 — Construction

**Effect: the world gains architecture the map files never had.**

Placing geometry. A single obelisk, then arrangements of them: a line with gaps
small enough to jump, a ring, a stair, a scatter.

The enabling fact, which sets both the possibility and the limit: in 3.3.5a the
**client** computes collision against a gameobject's model locally. A platform
spawned in mid-air is standable the instant it appears, without the server's
vmaps knowing it exists. Players can walk on it. Server-side pathfinding
cannot, so NPCs and bots will not path onto it.

| Issue | Title |
|-------|-------|
| 601 | The prop catalogue — which gameobject models are solid, and what they look like |
| 602 | `world.place` — spawn one gameobject at a computed position |
| 603 | Arrangements — line, ring, stair, scatter, computed from a shape spec |
| 604 | Jumpable spacing — gap and rise limits derived from movement, not guessed |
| 605 | `world.clear` — remove a placement by its receipt, leaving nothing behind |
| 606 | Custom prop templates — a "black obelisk" that is not any existing entry |

---

## Phase 7 — The Toolbox

**Effect: the operations become a vocabulary a machine can speak.**

Everything built in phases 1–6 gets registered, described, and rendered into
two surfaces from one source: a command-line interface for a person, and a
JSON Schema tool list for a model. Neither is written by hand.

This phase is where the closed set becomes a real, enumerable object rather
than a design intention.

| Issue | Title |
|-------|-------|
| 701 | The operation registry — declaration, validation, lookup |
| 702 | CLI generation — one subcommand per operation, with `--plan` |
| 703 | Tool-schema generation — JSON Schema from parameter descriptors |
| 704 | Argument coercion and refusal — what happens to a bad argument |
| 705 | The catalogue command — print the closed set, for humans and for review |

---

## Phase 8 — The Voice

**Effect: the vocabulary can be spoken by asking.**

The Claude API loop. A sentence goes in; a plan comes back; a person approves
it or it applies directly depending on the operation's blast radius; a report
comes back in prose.

| Issue | Title |
|-------|-------|
| 801 | HTTPS transport and JSON encoding for a Lua client |
| 802 | The conversation loop — tool_use, tool_result, stop reasons |
| 803 | World state as text — what the model is told before it chooses |
| 804 | Approval gates — which operations apply directly, which need a yes |
| 805 | Reporting — saying what was done, including when nothing was |
| 806 | Standing instructions — requests that persist past the sentence |

---

## Phase 9 — The Doors

**Effect: asking works from inside the game.**

Two entry points onto the same loop: a browser window on the machine, and a
character in the world you can talk to.

| Issue | Title |
|-------|-------|
| 901 | The browser door — a local page that talks to the loop |
| 902 | The in-game door — whisper a character, get an answer |
| 903 | Attribution — which player asked, and what they are allowed to ask for |
| 904 | Backgrounding — long work that reports when it finishes |
| 905 | Tabs — several pieces of work open, resolved one at a time |

---

## Phase 10 — Narration

**Effect: changes to the world become story.**

The capstone. A GM character narrates what is happening as it happens — not
reporting a database write, but describing the thing the write means. The
narrator is a voice with a name, emitting into a channel, driven by the same
receipts that record what was done.

| Issue | Title |
|-------|-------|
| 1001 | Voices — a named narrator with a manner of speaking |
| 1002 | Narrating a receipt — turning what happened into what is happening |
| 1003 | The channel — where narration appears and who hears it |
| 1004 | Narration that trails off — pacing, interruption, and not finishing |

---

---

## Phase 11 — Portage

**Effect: what was made here can be made again elsewhere.**

The capstone above the capstone. A session of building and narrating produces a
**queststorydungeon** — a plain text file describing an arrangement, which can
be applied to a world to produce that arrangement again.

The hard requirement is idempotence: applying it twice produces the same world
as applying it once. That reaches backward into every operation in the project,
because an operation phrased as "do this" places two obelisks when run twice,
and only an operation phrased as "make it so" places one.

And the line that makes it a story rather than a level: it is applied to the
characters who are already standing in the right place, turning them around
into the story props for its queststorydungeon.

| Issue | Title |
|-------|-------|
| 1101 | The queststorydungeon, exported |
| 1102 | Stable identity — naming an element so the name survives a new world |
| 1103 | `ensure` forms — every exportable operation stated as an end state |
| 1104 | Casting — matching who is present against the roles an arrangement wants |
| 1105 | The round trip — export, apply, export, and compare |

---

## Phase 12 — Likeness

**Effect: things can look like something the game never shipped.**

The one phase with a wall through the middle of it.

The server holds no art. It holds a **display id** and hands it to the client,
which looks the number up in a file it shipped with in 2010. So changing what
something looks like is a database write when the new look is one of the 21,381
displays already in the game — and a patch archive every player installs when it
is not.

Everything on the near side works today. Everything on the far side needs a
2010 model format with a rig, and a distribution story this project does not
have. The near side is built first and **announces that it is standing in for
the far side** every time it runs (issue 109), so the placeholder is never
mistaken for the finished thing.

| Issue | Title |
|-------|-------|
| 1200 | What a model actually is, and where the wall is |
| 1201 | `creature.reskin` — change a look, using what already ships |
| 1202 | The larder — keeping what was found, with its licence |
| 1203 | The scrapers — finding art out there **[the empty half]** |
| 1204 | Crossing the wall — a downloaded file becomes something the game shows |
| 1205 | "Change that goblin" — the sentence, resolved against what is in view |

---

## Phase Completion

For each phase:

1. Every issue resolved and moved to `issues/completed/`.
2. A phase demo built or rebuilt in `issues/completed/demos/`, showing the
   phase's own tools *and* recombining the previous phases' tools in some way
   they were not used before.
3. `issues/phase-N-progress.md` brought up to date.
4. A commit.

Phase demos are part of the deliverable, not a development artifact. They are
rebuilt as the project grows and released with it.

## The Test of the Ordering

Phases 1–6 are hands and levers. They are usable by a person at a terminal with
no model involved anywhere: `neuron teleport --roster guild --place ratchet-dock`
is phase 2 doing its whole job.

**If phases 8–10 are never built, the project is still useful.** That is the
test of whether the levers were designed properly, and it is the reason the
levers come first.
