# 1101 — The Queststorydungeon, Exported

## Status
- Phase: 11 (Portage)
- Blocked by: 106 (receipts), 605 (world.clear), 1002 (narrating a receipt)
- The capstone. Everything below it exists so this can exist.

## Current Behavior

Nothing exists. A session of building and narrating leaves receipts in a log
and changes in a world, and both are stuck where they happened. What was made
cannot be given to anyone, kept, or made again.

## Intended Behavior

A session produces a **queststorydungeon**: a plain text file describing an
arrangement, which can be applied to a world to produce that arrangement again.

> we should be able to output a datafile that is the queststorydungeon that was
> created, exported to .txt. It should be able to be idempotently applied to
> specific characters that had the correct location - so, turning everything
> around into the story props for it's queststorydungeon.

### What it holds

Not a database dump and not a save file. A **recipe**:

- **The props.** Which objects stand where, at what scale and facing. The
  obelisks, the platforms, the tower nobody had to find.
- **The placements.** Which characters stand where, wearing what, at what
  level, in which party.
- **The story.** The narration — the voice, and what it says, and when.
- **The anchor.** Where this whole arrangement sits, and relative to what.

It contains no game assets. It is text. It is a description of an arrangement,
and the arrangement is the author's.

### Idempotence is the hard requirement

Applying a queststorydungeon twice must produce the same world as applying it
once. Not "roughly the same" — the same.

That constraint reaches backward into every operation in the project and
changes how they must be written. An operation phrased as **"do this"** is not
idempotent: `world.place` called twice puts down two obelisks. An operation
phrased as **"make it so"** is: `world.ensure` called twice puts down one, and
the second call finds it already standing and does nothing.

So every operation that a queststorydungeon can contain needs a form that is a
statement about the desired end state rather than an instruction to act. That
is a real cost and it is worth paying, because the alternative is an artifact
you can only apply to a world that is in exactly the right condition, which is
an artifact nobody can use.

The mechanism: each element carries a **stable identity** derived from the
arrangement rather than from the database. An obelisk is not "gameobject row
418823"; it is "the third pillar of the north stair of THIS arrangement". On
apply, that identity is looked for first. Found means leave it; absent means
create it and record the mapping.

### "characters that had the correct location"

The line worth sitting with. A queststorydungeon does not create characters —
it **transforms the ones already standing in the right place**.

This is what makes it a *story* rather than a *level*. The people who were
there become the cast. Someone standing on the ridge when the arrangement is
applied becomes the figure on the ridge in the story. They are turned around
into the story props for its queststorydungeon.

Which means apply-time matching has to answer: who is close enough to a role's
anchor to fill it? And what happens when nobody is, or when several are? Those
are open questions below, and they are the interesting part of the feature.

### Text, on purpose

`.txt`, readable and editable by a person with no tooling.

A binary or a database dump would be smaller, faster, and worse — because the
thing being exported is a piece of writing. Somebody should be able to open a
queststorydungeon, read it, disagree with a line of narration, change it, and
apply it. The format is a document that happens to be executable, not a payload
that happens to be inspectable.

## Suggested Implementation Steps

1. Design the text format. It should read like a description, not like
   configuration. Sections for anchor, props, cast, and story. Decide this
   before anything else, because every other step serves it.
2. Write the stable-identity scheme: how an element in the file names itself
   such that the name survives being applied to a different world.
3. Write the exporter: read a range of receipts, curate them into elements,
   emit the file. Curation matters — a session contains false starts, and the
   arrangement is what was *meant*, not everything that was tried.
4. Give every exportable operation an `ensure` form: a statement of desired end
   state that is safe to apply repeatedly.
5. Write the applier: parse, resolve the anchor, match the cast against who is
   present, apply each element's `ensure` form, report what it created, what it
   found already correct, and what it could not fill.
6. Write the round-trip test, which is the only test that matters here: export
   an arrangement, apply it to an empty world, export again, and compare. The
   two files should say the same thing.
7. Write the `.info.md`.

## Open Questions

- **What happens when nobody is standing where a role expects?** Leave the role
  empty and say so? Spawn a bot to fill it? Refuse the whole application? The
  first is honest, the second is convenient, the third is safe, and they cannot
  all be right.
- **What happens when several people match a role?** First by distance is the
  obvious rule and is obviously sometimes wrong.
- **Is the transformation reversible?** Someone turned into a story prop
  presumably wants to be turned back. The receipt machinery can do it. Whether
  the queststorydungeon should carry its own undo, or rely on the receipt from
  applying it, is undecided.
- **How does an arrangement anchor to a world it was not built in?** Absolute
  coordinates only work in the world of origin. Relative-to-a-named-place works
  if the place exists. Relative-to-the-applier's-position always works and is
  the least controllable.
- **Does narration replay, or regenerate?** Replaying the exact lines makes the
  artifact faithful. Regenerating from the same situation makes it alive. The
  format could carry both — the line that was said, and the situation that
  produced it — and let the applier choose.
- **What is the unit?** One dungeon, one quest, one story? The compound word
  refuses to separate them, which is probably the correct answer and definitely
  an unusual one. Whether the file format should also refuse to separate them
  is a real question about what people will want to reuse.

## Related

- `LICENSE.md` — why the mechanics being widely known is what makes a
  queststorydungeon buildable by anyone at all
- Issue 106 — receipts, which this reads
- `docs/roadmap.md` — phase 11
