# 1008 — The Chatlog: Verbatim, Hot, and Cooling

## Status
- Phase: 10 (Narration)
- **Peer of 1005 (the scratchspace), not built on it** — the number is higher
  because it was specified later, and nothing here depends on the ring
- Blocked by: 1000 (playersheet)
- Blocks: 1007 (the resident narrator)

## Current Behavior

Two stores are designed and neither holds words. The scratchspace (1005) holds
atoms — impressions distilled to as few words as they survive in. The
playersheet (1000) holds the atoms that were deliberately kept.

An atom like `someone said hello, unanswered` records that a conversation
happened. It does not record what was said. So a creature spoken to twice in a
minute has no way to answer the second thing in terms of the first, because the
exact words were never anywhere.

## Intended Behavior

A third store, holding the **verbatim exchange** — what was said, in order, both
directions. Separate from the ring because it is a different kind of thing kept
for a different length of time.

### Three stores, three relationships to time

This is the shape worth seeing whole, because each store forgets differently and
the differences are the design:

| Store | Holds | Bound | How it forgets |
|-------|-------|-------|----------------|
| **chatlog** | verbatim speech | — | **cools**: relevance decays over ~30 seconds |
| **scratchspace** | atoms | N slots | **falls off**: new pushes old out, by position |
| **playersheet** | atoms | — | **never**, until `forget` strikes one |

Only the chatlog has a time dimension at all. The ring evicts by position, the
sheet does not evict, and the chatlog **does not evict either** — it dims. The
words stay; what changes is how much of the creature's attention they get.

### The pipeline this makes

Read downward and each step loses fidelity and gains duration, which is what
memory is:

```
    chatlog      verbatim words      seconds        cools by time
       │
       │  distilled by `note` into an impression
       ▼
    ring         one atom            N slots        falls off by position
       │
       │  chosen by `remember`
       ▼
    sheet        one atom            forever        struck only by `forget`
```

The consequence is worth stating plainly because it is the thing that makes this
feel right: **when the chatlog cools, what is left is the atom.** The creature
remembers that it talked to you and roughly what about, and not your exact
words. That is how conversational memory actually works in the thing this is
imitating, and it arrives here for free rather than being modelled.

### Relevance is a share of the context, not a display setting

Relevance is a number from 0 to 1 that decides **how much of the model's context
budget the chatlog gets**, competing against the ring and the sheet for a fixed
total.

- At **1.0** the creature is in a conversation and that is what it is thinking
  about. The chatlog dominates; the ring and sheet get what is left.
- At **0.1** it is a line saying *you were speaking with somebody a minute ago*,
  and the ring and the sheet have the room.

Making it a share rather than a flag is what makes it a mechanic. A creature
mid-conversation genuinely has less attention for the cherries, and that is
correct rather than a limitation.

### Any change resets it to full

The moment a line is appended the relevance snaps back to 1.0 and begins cooling
again. **Both directions count** — something heard, and something the creature
itself said.

That the creature's own speech keeps the log hot is what makes it a conversation
rather than a broadcast. A creature part-way through saying two things does not
cool between them and wander off mid-thought.

And the reset being instant, rather than a ramp, is what means you never have to
re-establish a conversation. Speak after twenty-eight seconds of silence and the
creature is fully back in it, with every word still there, because nothing was
ever deleted — only dimmed.

### The shape of the curve

Exponential toward a resting value, parameterised by half-life, rather than a
straight line to zero. Two reasons:

- A straight line has a corner at the end: relevance is falling steadily and
  then is abruptly nothing. A creature drifts out of a conversation; it does not
  fall out of one.
- Half-life is the parameter somebody can reason about. "Half gone in eight
  seconds" is a sentence about behaviour. "Slope of −0.033" is not.

The resting value is configurable and defaults to zero. A non-zero resting value
would be a creature that never fully leaves a conversation, which is a different
creature and possibly a better one, and the knob is there to find out.

## Suggested Implementation Steps

1. Write the decay curve and the budget split first. Both are pure arithmetic,
   need no world, and hold the only real decisions here.
2. Split a fixed budget across the three stores by relevance, with the
   allocations summing **exactly** to the budget. Naive rounding of three
   proportions does not, and a context budget that is three lines over is a
   truncated prompt.
3. Write the chatlog as an append-only list of `{ who, said, at }`. Verbatim —
   no distillation on the way in, since distilling is what `note` is for.
4. Reset relevance on append, from either direction, in one place. Two reset
   paths is how one of them ends up not resetting.
5. Feed it from the resident hand's speech hooks.
6. Test the decay against the clock, not against a tick count — see the open
   question, which is a real interaction between two knobs.

## Open Questions

- **Does narration count as speech that resets the timer?** If a creature
  narrating its afternoon appends to the chatlog, it holds itself at 1.0 forever
  and never cools enough to think about anything else. Probably narration
  directed at nobody does not reset it and speech directed at a person does —
  but that is a distinction that has to exist somewhere, and it does not yet.
- **Thirty seconds of what?** Wall clock, or turns of the creature's own loop?
  If the loop turns once a minute (issue 1007), a thirty-second decay means the
  log is always cold by the time the creature thinks, and the two knobs are
  fighting. This is the interaction most likely to make the feature feel broken
  while both numbers look reasonable on their own.
- **One chatlog or one per conversation?** With one, a second person walking up
  interleaves with the first and the creature answers A using B's context. With
  one per person, relevance is per-conversation and a creature can hold two at
  different temperatures — which is more true and more expensive.
- **Does the chatlog survive the creature leaving?** Walking a mile away from
  somebody mid-sentence should probably cool it faster than silence does, which
  would make relevance a function of distance as well as time.
- **What resets it for a ghost that changed hosts?** The sheet moves with the
  ghost. A conversation half-finished in a previous body is either still warm or
  is not, and that answer says something about what a ghost is.

## Related

- Issue 1005 — the ring, and `note`, which is how a chatlog line becomes an atom
- Issue 1007 — the narrator, which reads all three
