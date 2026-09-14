# 1000 — The Playersheet: Long Memory, For Everything Alive

## Status
- Phase: 10 (Narration) — the foundation of it, below voices
- Blocked by: 107 (enums)
- Blocks: 1005 (scratchspace), 1006 (NPC tools), 1007 (the resident narrator)

## Current Behavior

Nothing remembers anything. A creature in the world is rows in
`creature`/`creature_template` and a character is rows in `characters`, and
between them there is nowhere to put a fact that a creature *chose* to keep.

The closest thing that exists is the receipt log, which records what neuron did
from outside. It has no idea what anybody in the world noticed.

## Intended Behavior

Every creature gets a sheet. Not just player characters — **monsters too, and
the traveler NPCs, and the bots**. One shape for everything alive, because a
narrator that has to ask "is this a player or a monster" before it can find out
what somebody knows is a narrator with two codebases.

Sheets are made **on the go**. There is no pre-population pass and no migration
that creates twenty-five thousand empty sheets. A sheet comes into existence the
first time something writes to it, which means the population of sheets is
exactly the population of creatures that have had a thought.

### What is on it

The sheet is the **long** half of memory. Its counterpart is the scratchspace
(issue 1005), which holds what is happening nearby right now and is bounded.
The division is not by subject but by duration:

| Kind | Example | Why it is long |
|------|---------|----------------|
| identity | what I am, what I answer to | it does not change between one hour and the next |
| durable place-fact | "the barracks is building number 4" | the barracks will still be building four tomorrow |
| durable world-fact | "there's cherries in a glade over there" | the glade does not move |
| standing relation | who I know, and how that went | accumulates rather than expires |
| storyline state | what I am in the middle of | the thread that makes a sequence of acts a story |

### Remembering is an act, not a side effect

**The creature writes its own sheet, deliberately.** Nothing observes a creature
and files a fact on its behalf. Seeing a glade full of cherries puts an atom in
the scratchspace; *deciding that matters* is a separate act — the `remember`
tool — and it is rare, where noting an impression is constant.

This is the design's centre of gravity and it should not be softened for
convenience. A creature that automatically remembers everything it saw has no
interior — its sheet is a log of its sensors. A creature that must spend an act
to remember has preferences, and its sheet is a record of what it cared about.
The sheet read back later is therefore evidence of character rather than
evidence of exposure.

Both halves are editable at will, and `forget` strikes one atom from either. "The
barracks is building number 4" is a thing somebody concluded, and concluding
wrongly is allowed — so unconcluding has to be possible, or the sheet only ever
accumulates and never corrects.

### What a sheet belongs to: bodies, ghosts, and hosts

Two levels of identity, and which one a creature gets is earned rather than
given.

A **body** is an instantiation. A spawned wolf is a row with a guid, and the
guid is the body's, not the wolf's. Its sheet is keyed on that guid and dies
when the body does. **This is correct and not a loss.** Monsters are instances of
a template; the world makes them constantly and unmakes them constantly, and a
wolf that remembered its previous seventeen deaths would be a much stranger thing
than the design is asking for.

A **ghost** is an identity that is not tied to a body. It has a sheet that
outlives whatever it is currently standing in. An NPC is a ghost.

**A body becomes a ghost when it is given behavior.** That is the whole
promotion rule. Something the world spawns and forgets is a body; something
somebody gave a way of acting to is a ghost, and from then on its sheet belongs
to it rather than to the flesh it is in. A ghost that has behavior **can learn
new hosts** — move into another body, keeping everything it knows, because what
it knows was never stored in the body.

Note the shape this shares with the memory model, because it is the same shape
twice:

| | ephemeral by default | persists when | the act |
|---|---|---|---|
| memory | an atom in the ring | it is deliberately kept | `remember` |
| identity | a body's sheet | behavior is given | becoming a ghost |

In both, nothing persists by accumulating. It persists because something
deliberate happened to it. That is worth stating once here because it will be
tempting, in both places, to add a rule that promotes things automatically past
some threshold — and in both places that rule would replace a creature's
preferences with a machine's arithmetic.

## Suggested Implementation Steps

1. Key a sheet on the creature's guid. For a body that is the whole scheme and
   the sheet is expected to die with it.
2. Build the ghost layer above that: a ghost id, a sheet belonging to it, and a
   current host. A body with no ghost reads its guid-keyed sheet and nothing
   else, so the common case costs nothing.
3. Write becoming-a-ghost as the moment behavior is attached, and write it as an
   explicit act with a record, not as a side effect of a creature happening to
   be interesting.
4. Write the sheet as an ordered list of entries rather than a fixed set of
   fields. A fixed schema decides in advance what a creature is allowed to have
   noticed, which is the opposite of what this is for.
5. Give each entry: what kind it is, the text of it, when it was written, and
   what it was written from — scratch promotion, or first-hand, or told by
   somebody.
6. Write the read and write paths for the resident hand first, since the
   creature doing the remembering is inside the world.
7. Write the cold-hand read path second, so `neuron` from outside can print a
   creature's sheet without the world being up. Reading somebody's memory is the
   thing that makes this debuggable.
8. Test both levels against the same wolf: spawn one, have it write a fact,
   kill it, respawn it, and confirm the fact is gone. Then give one behavior,
   do the same, and confirm the fact survived into the new body.

## Open Questions

- **What makes something "given behavior"?** The promotion rule turns on it and
  it is not yet defined. A bot with a combat rotation has behavior in one sense
  and is plainly not a ghost. Probably it means behavior neuron installed
  deliberately, which makes the boundary an act somebody took rather than a
  property to be measured — but that needs saying rather than assuming.
- **Can a ghost be in two hosts?** Nothing yet says no, and a ghost with two
  bodies has one sheet and two scratchspaces, which is either a bug or a very
  interesting creature.
- **What happens to a ghost with no host?** It has a sheet and nowhere to stand.
  Either it waits, or it is not running, and the difference decides whether a
  ghost can be moved between bodies without a gap in its afternoon.
- **Where does the sheet live?** A table in `acore_characters` gets backups and
  transactions for free, and costs a database round trip on the worldserver's
  tick. A file in the ALE script directory is instant and is not backed up by
  anything. The resident hand can reach both.
- **What happens to a sheet when its creature is retired?** `character.retire`
  removes rows across thirty-nine tables and proves it with a dangling-row
  check. A sheet is a fortieth, and forgetting to add it there means the
  dangling check starts reporting residue nobody put there deliberately.
- **Can one creature read another's sheet?** If yes, "telling somebody
  something" is a real mechanic and gossip is possible. If no, every creature is
  sealed and the only transmission is speech somebody chose to say out loud.
- **Is there a size limit?** An unbounded sheet is a creature that never forgets,
  which the scratchspace's whole design says is the wrong shape for the short
  half. Whether it is also the wrong shape for the long half is unanswered.

## Related

- Issue 1005 — the scratchspace, and why remembering costs an act
- Issue 1007 — the resident narrator, the first creature to have one
