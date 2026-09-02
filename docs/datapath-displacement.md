# Datapath — Displacement

*Moving characters through space.*

## The Path

```
  neuron teleport --roster 'bots hunters 20' --place ratchet
        │
        ▼
  ┌──────────────────────────────────────────────────────────────┐
  │ RESOLVE THE PLACE                                            │
  │   project table first, then the game's own game_tele         │
  │   1,989 game locations exist; ambiguity returns ALL matches   │
  └──────────────────────────────────────────────────────────────┘
        │
        ▼
  ┌──────────────────────────────────────────────────────────────┐
  │ RESOLVE THE ROSTER                                           │
  │   a name, a comma list, or a query -- ONE database round trip │
  │   orphans excluded by default, and the exclusion is reported  │
  └──────────────────────────────────────────────────────────────┘
        │
        ▼
  ┌──────────────────────────────────────────────────────────────┐
  │ ONE STEP PER CHARACTER, HAND CHOSEN PER CHARACTER            │
  │                                                              │
  │   offline ──► cold : the row IS their position                │
  │   online  ──► live : a row write would be overwritten         │
  └──────────────────────────────────────────────────────────────┘
        │
        ├──────────► --plan? print the steps. STOP.
        │
        ▼
  ┌──────────────────────────────────────────────────────────────┐
  │ PER STEP, AT APPLY TIME                                      │
  │   guard: is this character online NOW?                        │
  │   capture: read the columns about to be overwritten           │
  │   write                                                       │
  │   record: prior values AND written values                     │
  └──────────────────────────────────────────────────────────────┘
        │
        ▼
     receipt  ──────────► neuron return --receipt <id>
```

## The Place Book

The world database ships `game_tele` — 1,989 named locations on the live
deployment — and it is the table AzerothCore's own teleport command reads.

That produces the symmetry the whole phase rests on: the live hand's
`tele name <character> <location>` takes **exactly these names**.

| Hand | What it does with the name `ratchet` |
|------|--------------------------------------|
| live | Passes it through: `tele name Grast Ratchet` |
| cold | Looks up its coordinates and writes them onto the row |

No translation layer and no mapping table, so the two hands cannot disagree
about where `ratchet` is unless the database disagrees with itself.

Project places — `the-ridge`, `camp-north` — live in `neuron_place` in the
**characters** database, not the world database. The world database is
regenerated wholesale when a deployment re-imports upstream data; a project
table there is a table that vanishes on the next server update.

A project place **cannot be used by the live hand**, because the game does not
know its name. A place record carries `known_to_game` so no caller has to
remember that rule, and an online character being sent to a project place is
refused with that as the reason.

### Name folding

Game names are `MenethilHarbor`, `TheBarrens` — camel-cased and unspaced.
Matching lowercases and strips everything that is not a letter or digit, on
**both** sides of the comparison, using the same function. Two normalisers that
drift produce a lookup that works in a test and not in life.

An ambiguous name returns every candidate. `harbor` matches five places and
resolving that by guessing, then moving forty characters, is not recoverable.

## The Roster

The lookup table the project was asked for. Four forms, resolved **at use time**:

| Form | Example |
|------|---------|
| One name | `Grast` |
| A list | `Grast,Wenna,Aalia` |
| A query | `bots hunters 18-20` |
| A group | *(phase 4)* |

Resolution at use time rather than definition time is deliberate: a roster
meaning "bots between 18 and 20" means different characters next week, and a
stored list would silently go stale and move the wrong forty.

The query vocabulary is deliberately small — level or level range, class, race,
bot/person/orphan, online/offline. It is a filter, not a language. **An
unrecognised word is an error**, because a typo that silently matches everything
is how a roster resolves to twenty-five thousand characters.

Three guards on the result, all of them reported rather than silent:

- **Missing names** are returned, never dropped. Thirty-eight of forty moved and
  reported as success is worse than a refusal.
- **Orphans are excluded** by default. The live deployment holds 900 characters
  with no account row; sweeping them into bulk operations is a slow way to find
  out they exist.
- **A ceiling** is applied and reported, so a truncated roster is visibly
  truncated rather than quietly complete.

## Which Hand, Per Character

Not per operation. Two characters in the same roster get different answers.

| The character is | Hand | Why |
|------------------|------|-----|
| offline | cold | Nothing holds their state; the row **is** their position |
| online | live | A row write is overwritten by the server's next save |

An offline character teleported by database write appears at the destination on
their next login. An online character teleported by game master command moves
immediately, in front of everyone standing there.

The live hand cannot help an offline character at all — a game master teleport
needs a character present in the world. This is worth stating because it is the
obvious thing to try.

## What Gets Written

`map`, `position_x`, `position_y`, `position_z`, `orientation`.

**The map is not optional.** Writing the three coordinates without it produces a
character at the right numbers on the wrong continent, which looks exactly like
the teleport having done nothing.

**`zone` is deliberately not written.** It is stored on the row, and the server
recomputes it from the position at login. A stale zone beside a fresh position
produces a character who is in Ratchet and believes they are in Menethil.

## Receipts and Return

Every cold step records two things:

- **`restores`** — the columns as they were before, read immediately before the
  write. One extra query per write, and it buys the entire undo.
- **`wrote`** — the values the step put there.

Both are needed, and the reason is drift. Knowing only the prior value, an undo
cannot tell "nobody has touched them since" from "they have moved twice" —
because in both cases the current position differs from the prior one. Differing
from the prior position is what a successful change *means*. Comparing against
what was **written** is the question actually worth asking.

So `neuron return --receipt <id>` reports which characters have moved since,
and does not refuse — the person deciding has context the code does not.

Reversal is keyed by **GUID**, never by name. A character can be renamed, and a
freed name can be taken by somebody else.

Only steps that both succeeded and captured a prior value are reversed. Undoing
a step that never ran would move a character who was never moved.

## Verified

The full cycle was run against the live deployment: two bots moved to Ratchet,
one moved on to Astranaar, the first receipt reversed. Drift was reported for
the one that had moved and not for the one that had not, and both characters
returned to their original coordinates to the hundredth of a yard, map included.
