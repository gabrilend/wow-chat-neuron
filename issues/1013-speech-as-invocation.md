# 1013 — When Saying It Makes It Happen

## Status
- Phase: 10 (Narration)
- Blocked by: 1007 (the resident narrator), 802 (the loop)
- Blocks: nothing
- **Read the hazards section before building any of this.**

## Current Behavior

The narrator and the lever-puller are two different acts. A model calls
`world.spawn` to make something happen and separately says a sentence about it.
Speech is downstream of action, always, and describes what already occurred.

## Intended Behavior

**The narration is the invocation.** A creature telling its story says certain
words, and those words fire.

```
   "...and out of the treeline came a WOLF, three of them, hungry —"
                                       └──────┬──────┘
                                    world.spawn, creature=wolf, count=3
```

Not a tool call rendered into prose afterwards. The prose **is** the call, read
as it is produced, with the connective text — *and out of the treeline came*,
*hungry* — filtered away as texture around the words that carry.

### Why this is different from tool calling, and better in one specific way

A tool call is a decision made in one register and described in another. The
model chooses `world.spawn`, gets a plan back, and then writes a sentence about
wolves. Two acts, and the sentence can disagree with the call — it can say four
wolves when three were spawned, and nothing notices.

Speech-as-invocation cannot disagree with itself, because there is only one
utterance. What was said **is** what happened.

### Streaming, so it fires as it is typed

Read the stream, and fire on the word rather than at the end of the turn. The
wolves appear while the sentence is still being written, which is the whole
feeling of the thing: the world assembling itself a half-second behind the
telling, rather than after it.

### The accidents are the point

If the trigger words are common ones, a narrator will say them **without
meaning to**. Talking about a wolf that is not there spawns a wolf.

This should be read as a feature and designed for, not guarded against. It
produces events that were not caused by anything previously related to them —
which is exactly the texture a world made only of deliberate acts never has. A
storyteller who cannot stop summoning what they mention is a better character
than one in perfect control.

**And the way to have more of it is to make the words easy to say.** Common
nouns, ordinary verbs, no punctuation, no prefix. A vocabulary a narrator has to
reach for produces nothing accidental; one it cannot avoid produces a world that
keeps surprising the thing narrating it.

### The narrator has to be able to try not to

If saying a word fires it, then a narrator that wants to *mention* a wolf
without summoning one needs a way — and it must be effortful rather than free,
or nobody ever triggers anything by accident again. Some possibilities, none
obviously right:

- **Naming it in the past.** *There had been wolves* does not fire; *there are
  wolves* does. Tense as the safety, which is beautiful and hard.
- **A held breath.** A marker that suppresses the next trigger, costing the
  narrator an act — the same shape as `remember` costing an act in issue 1005.
- **Nothing at all.** The narrator simply cannot mention what it will not
  summon, and learns to talk around things. That is the strongest version and
  the most alarming.

## The hazards, which are not small

**Every one of these is a way for this to be terrible rather than good.**

- **An irreversible word must never be sayable.** `character.retire` cannot be
  undone. A narrator saying *and then they were gone forever* must not be able
  to mean it. The `kind` enum already separates `final` from `change`, and this
  feature must be built on top of that separation rather than beside it: the
  sayable vocabulary is `change` and `read` only, enforced where the words are
  registered, not by a list somebody maintains.
- **A trigger inside quoted speech.** A narrator relaying what a player said —
  *she asked about the wolves* — would fire on the player's word. Whether
  quotation suppresses is a question with no obvious answer and a very obvious
  failure.
- **Repetition.** A word said three times in a sentence spawns three times.
  Almost certainly wrong, and "almost" is doing real work — sometimes three is
  what was meant.
- **A player can make the narrator talk.** Anything a person says that the
  narrator repeats is a person choosing what appears in the world, without ever
  touching a lever. That is either the best emergent thing here or a complete
  loss of control, depending entirely on what is sayable.
- **The plan-then-confirm rule is gone.** Every other route to changing the
  world shows a plan and waits. This one cannot — the point is immediacy. So
  the whole safety model rests on the sayable vocabulary being small,
  reversible, and cheap, rather than on anybody agreeing to anything.

## Suggested Implementation Steps

1. Build it **off**, and off by default, behind an explicit enable. It is a
   world-altering feature with no confirmation step.
2. Start with one word, one operation, fully reversible, in one place. A wolf.
3. Fire at end of turn first, not on the stream. Streaming is the good version
   and adds a second failure mode to a thing that already has several.
4. Take the sayable vocabulary from the registry, filtered to non-`final`, so a
   word that becomes irreversible stops being sayable in the same edit.
5. Write every firing to the receipt log with the sentence that caused it. The
   only way to understand a world built like this is to read what was said.
6. Only then: streaming, multiple words, and any suppression mechanism.

## Open Questions

- **Does the narrator know this is happening?** A creature that knows its words
  are load-bearing speaks very differently from one that does not, and the
  second is much stranger and more alive.
- **What happens when two narrators are in earshot?** One says wolf, the other
  repeats it, and the repetition fires again. Nothing yet stops a resonance.
- **Where do the spawned things go?** *A wolf* names no place. Near the speaker
  is the obvious answer, and it means a narrator describing somewhere far away
  furnishes the room it is standing in.
- **Is this one feature or two?** Firing on speech, and doing it mid-stream, are
  separable — and the second is where all the difficulty is.

## Related

- Issue 1007 — the narrator this belongs to
- Issue 1005 — where an act costing something is already the design
- `src/025-enums/028-kinds.lua` — the `final` marking this must be built on
