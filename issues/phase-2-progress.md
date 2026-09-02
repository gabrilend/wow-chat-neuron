# Phase 2 — Displacement: Progress

**Effect: anyone can be anywhere.**

## Where it stands

| Issue | Title | Status |
|-------|-------|--------|
| 201 | The place book | Done, verified live |
| 202 | Rosters | Done, verified live |
| 203 | `character.teleport` | Done, verified live (cold hand only) |
| 204 | Scatter and formation | Not started |
| 205 | `character.return` | Done, verified live |

The full cycle has been run against the live deployment. Two companion
characters were moved to Ratchet, one was moved on to Astranaar, and the first
receipt was reversed — both returned to their original coordinates to the
hundredth of a yard, map included, and the world was left exactly as it was
found.

The **live hand is still unexercised**. Every step taken so far has been a cold
one, because no worldserver has been running. Teleporting a logged-in character
by game master command is written and unproven.

## The journey

**The place book turned out to be mostly discovery.** The world database already
ships `game_tele` — 1,989 named locations — and it is the table AzerothCore's own
teleport command reads. Which produces the symmetry the whole phase rests on: one
name works through both hands, because the live hand passes it straight through
to a command that takes exactly these names, and the cold hand looks up its
coordinates. No translation layer means the two hands cannot disagree about where
Ratchet is unless the database disagrees with itself. Almost none of this had to
be invented.

**Ambiguity is reported rather than resolved.** `harbor` matches five places.
Picking one and then moving forty characters there is not a recoverable mistake,
so the resolver returns all five and stops.

**A design mistake, caught by running the thing.** The first version of the undo
compared each character's current position against the position being restored
*to*, and reported drift when they differed — which is always, because differing
from where you started is what a successful move means. Every undo reported that
everybody had drifted.

The fix reached back into the receipt format. A receipt now records what a step
**wrote** as well as what it overwrote, and drift is measured against the written
value. Knowing only the prior value, an undo genuinely cannot distinguish
"nobody has touched them since" from "they have moved twice". Both were needed
all along and only one had been written down.

Verified afterwards by moving two characters, moving one of them again, and
reversing the first receipt: drift was reported for the one that had moved and
not for the one that had not.

**Coordinates need a tolerance, not equality.** The position columns are 4-byte
floats and the values pass through Lua doubles, so an untouched character reads
back a fraction of a yard from what was written. Exact comparison reported every
character as drifted. Half a yard is the tolerance; it is a real fact about the
schema rather than a fudge.

**Two fields that are easy to get wrong and expensive to debug.** The map must be
written alongside the coordinates, or a character lands at the right numbers on
the wrong continent — which looks exactly like the teleport silently failing. And
the zone must *not* be written, because the server recomputes it from the
position at login; a stale zone beside a fresh position produces a character who
is in Ratchet and believes they are in Menethil. Both are recorded in the code
where the write happens.

**Patching Lua source with Lua patterns kept failing silently.** Three separate
edits matched zero times and reported success, because a zero-match `gsub` is not
an error. Lua source is full of the characters patterns treat as syntax. Switched
to plain-text find-and-splice with an assertion on the anchor, which fails loudly
when the anchor is not there. Worth remembering: the tooling for editing this
project's own source should not use the pattern language.

## A schema change to the deployment

`neuron_place` was created in the deployment's characters database. It is empty,
it is prefixed so its owner is obvious, and it is the project table issue 201
calls for. It lives in the characters database rather than the world database
because the world database is regenerated wholesale on an upstream re-import, and
a project table there would vanish on the next server update.

## Open questions carried forward

From issue 201: whether project places should be per-deployment or global — a
name like `the-ridge` means a coordinate in one world, and carrying it to another
is exactly what a queststorydungeon must do and exactly what a place book must
not do silently. Also whether a place carries a facing, and what guards an
instance-map destination needs.

From issue 202: whether rosters may contain rosters, whether a saved roster
should be able to pin rather than re-resolve, and how large a roster should get
before it stops and asks.

From issue 203: what happens to a dead character's corpse when the living body is
moved, and whether everyone landing on one coordinate is acceptable until issue
204 exists. Currently it is a pile.

From issue 205: how long a receipt stays useful for reversal, and whether
reversing a partial receipt should be allowed. It currently is, on the grounds
that a half-changed world is exactly when somebody most needs the tool.

None of these block phase 3.
