# 1205 — "Change That Goblin"

## Status
- Phase: 12 (Likeness) — the capstone
- Blocked by: 1201 (reskin), 1009 (seeing instead of querying)
- Blocks: nothing

## Current Behavior

The vocabulary takes names and numbers. `world.creatures` wants a type;
`creature.reskin` wants an entry number and a display id.

Nobody standing in a world says either. They say *that goblin* — pointing, with
a word that is not a name and a gesture that is not a coordinate.

## Intended Behavior

The whole sentence, resolved.

```
    "change that goblin"
      │
      ├── that     ── which one? the one in view, nearest the middle of the frame
      ├── goblin   ── is that what it is? the creature's own name says so
      └── change   ── to what? unstated, and the interesting part
```

### "That" is a question for the camera, not the database

*That* means the one being looked at. A database query returns every goblin in
the world; the person means one, and which one is a fact about **where they are
standing and what is in front of them** — which is what phase 10's perception is
for.

So `that` resolves against the current frame: the recognised thing nearest the
centre, or the one most recently in a `seen` atom. If nothing is in view, the
honest answer is *I cannot see a goblin* — not a list of four hundred.

### "Goblin" is a check, not a lookup

The person has already identified it. The word's job is to **confirm agreement
about the referent** — if what is in view is a murloc, saying so is far more
useful than reskinning it.

A mismatch is a question back, not a refusal and not a guess.

### "Change" is the underspecified part, and should stay that way

Change it to *what*? The sentence does not say, and that is not sloppiness —
the person means *make it different, surprise me*, or they mean something they
have not put into words yet.

Two honest responses, and the model chooses:

- **Propose.** Pick a display, say what it is, show the plan. Most requests
  phrased this loosely want somebody else to decide.
- **Ask one question.** *Bigger, or a different creature entirely?* One question,
  not a form.

What it must not do is pick silently and apply. The plan-then-confirm path
already prevents that, which is why this whole sentence is safe to attempt.

### It is a stub, all the way down

`creature.reskin` picks from what the game ships and says so (issue 1201). So
this sentence works end to end today and the answer carries the notice: the
goblin does become something else, and the person is told the something-else
came from a shipped palette rather than from the web.

## Suggested Implementation Steps

1. Resolve `that` against the scratchspace first — the most recent `seen` atom
   matching the word. Cheapest, and usually right.
2. Fall back to the current frame's recognised things, nearest to centre.
3. Refuse plainly when nothing is in view. *I cannot see a goblin from here* is
   an answer; four hundred rows is not.
4. Let the model propose the new display and describe it in words.
5. Carry the stub notice into the answer, not only into the plan.

## Open Questions

- **What if there are two?** Two goblins in frame is the common case, and
  *nearest the centre* is a rule that will sometimes pick the other one. A plan
  naming which — and where it is standing — lets a person catch it before
  agreeing.
- **Does "that" persist?** After changing one, *make it bigger too* should mean
  the same creature. That needs a referent held between turns.
- **What about "all the goblins here"?** A different and easier question — it is
  a roster — and the words are close enough that mishearing one for the other
  changes forty creatures instead of one.
- **How is the new look described?** *Now a Forest Troll Berserker* is a name
  from the database. Whether that means anything to a person depends on whether
  they know the game.

## Related

- Issue 1201 — the word this sentence reaches
- Issue 1009 — perception, which is what `that` is asked of
