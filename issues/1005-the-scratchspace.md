# 1005 — The Scratchspace: N Slots of What Is Going On Around Here

## Status
- Phase: 10 (Narration)
- Blocked by: 1000 (the playersheet)
- Blocks: 1007 (the resident narrator)

## Current Behavior

Nothing holds a creature's sense of the present. The playersheet (issue 1000)
holds what a creature decided to keep, and there is no place for the much larger
volume of things it has merely noticed and not yet decided about.

## Intended Behavior

A ring of **N slots**, per creature, holding what is happening in the area.
First-person, present tense, and short.

### A slot holds an atom

An **atom** is a thought-idea distilled to as few words as it can survive in. A
core kernel truth. Not a description of what happened — the *impression* left by
it, with everything inessential already gone.

```
    [1] player in green at the well
    [2] north door open
    [3] cherries in the glade east
    [4] someone said hello, unanswered
```

The distillation is the work, and it happens on the way in rather than on the
way out. An atom written as a paragraph is a paragraph that has to be re-read
and re-understood every time the creature thinks; an atom written as four words
is a thing that can be held alongside thirty others. The compression is what
makes a small ring hold a whole situation.

An atom is also the unit everything else operates on. Promotion moves one atom.
Forgetting removes one atom. The narrator reads them in order. Nothing in the
system addresses half of one.

N is a knob and it is the interesting one. A creature with three slots lives
entirely in the moment and will lose the cherries before it has walked to them.
A creature with forty holds a whole scene and can act on something it saw ten
minutes ago. Setting N per creature is how a wolf and an innkeeper differ
without either needing different code.

### Bounded is the mechanic, not the limitation

The scratchspace is full almost immediately, and when a new observation arrives
the oldest one falls off. **That eviction is what makes remembering cost
something.** A fact about to fall off is gone unless the creature spends an act
moving it to the playersheet — and spending that act is a choice about what
matters.

This is why the bound is not a performance concession that a bigger machine
would remove. Unbounded scratch and a playersheet become the same thing, the
promotion act becomes pointless, and the creature's sheet stops being evidence
of what it cared about. The pressure is the feature.

"There's cherries in a glade over there" begins in a slot because the creature
walked past a glade. It reaches the sheet only if the creature, before that slot
is overwritten, decides it is the sort of thing it wants to still know
tomorrow.

### Three tools, and their frequencies are the character

Every write to memory is an act the creature takes. The three are not equally
common, and the ratio between them is what a personality is made of:

| Tool | How often | What it does |
|------|-----------|--------------|
| **note** | constant | Write an impression into a slot. The cheap one; this is most of what a creature does. |
| **remember** | rare | Move one atom from a slot onto the playersheet. Consciously deciding this is worth still knowing tomorrow. |
| **forget** | rare | Strike one specific atom out, from either place. |

**Forgetting is deliberate even though eviction is automatic.** The ring drops
the oldest; forgetting drops a *chosen* one, and the three reasons that matters
are all different from age:

- An atom went false. The north door is shut now. Letting it age out means
  acting on something untrue for however long the ring takes to turn, and a
  creature that walks to a door it believes is open is a creature that looks
  broken rather than mistaken.
- The creature wants room *now*, before it walks into a room worth seeing.
  Clearing a slot on purpose is making space for something anticipated.
- Something on the sheet is no longer held. A durable fact concluded wrongly —
  "the barracks is building number 4", when it is not — has to be strikeable, or
  the sheet accumulates errors it can never shed.

The asymmetry is the point. Noting is constant, so the ring churns. Remembering
is rare, so the sheet stays small and everything on it was chosen. Forgetting is
rare, so a struck atom means something happened rather than time passing.

### Where the contents come from

Three sources, and each entry records which:

| Source | Example |
|--------|---------|
| seen | a player walked up; a door is open; there is fruit here |
| done | I opened the door; I picked up a carrot |
| said | somebody spoke to me; I answered |

`done` entries are what let the narration engine (issue 1007) describe a
sequence of acts as a storyline rather than a list — the creature's own actions
are in the same buffer as the world's, in the order they happened, from one
point of view.

## Suggested Implementation Steps

1. Write the ring: N slots holding atoms, oldest evicted, per-creature N,
   pinning supported.
2. Write it as a first-class thing the creature holds rather than a cache
   something else maintains for it. It is memory, not an index.
3. Write the three memory tools — note, remember, forget — as tools the
   creature calls, never as automatic rules with thresholds. A threshold is a
   machine deciding what mattered.
4. Make forget address one atom exactly, in either store. A forget that clears
   a range is a creature losing its afternoon, which is a different thing and
   should be a different word if it is wanted at all.
5. Give every entry a source and a time, since the narrator reads both.
6. Feed it from the resident hand's event hooks: something entered range,
   something was said, a tool was used.
7. Test the pressure directly: give a creature three slots, walk it past four
   interesting things, and confirm exactly what it kept is what it chose.

## Open Questions

- **Does distance evict, or only age?** A creature that walked a mile still holds
  a slot saying a door is open, and the door is now somewhere it cannot see. Age
  alone makes stale slots; distance alone makes a creature forget the room it
  just left the moment it steps outside.
- **What is a good default N?** Unknown, and it is the number that most decides
  how a creature reads to a person watching it. It should be found by watching,
  not chosen, and the finding belongs in `docs/balance-updates.md`.
- **Does the creature see its own scratchspace as text?** If it does, the slots
  are its prompt and the wording of a slot is doing real work. If it does not,
  something has to render them, and that renderer is then a second author.
- **Can a slot be wrong?** A creature that misreads a situation writes an atom
  that is false, acts on it, and is mistaken. That is either a bug or the best
  thing here. `forget` is what makes it recoverable rather than permanent.
- **How short is an atom allowed to be?** Distilling too far produces something
  only the creature that wrote it can read back, which is fine until the
  narrator has to say it out loud. There may be a floor, and it may be a knob.
- **Can a creature forget something on purpose that it wishes it could not?** A
  struck atom is gone. If the same thing is in front of it again it will note it
  again, which means deliberate forgetting is only durable for things that do
  not recur — and that asymmetry is worth knowing before it surprises somebody.

## Related

- Issue 1008 — the chatlog, which holds the words an atom was distilled from
- Issue 1000 — the playersheet, where an atom goes when it survives
- Issue 1006 — NPC tools, which write `done` entries as they run
