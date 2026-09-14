# 1007 — The Resident Narrator: Somebody Who Lives There

## Status
- Phase: 10 (Narration) — the capstone
- Blocked by: 1000 (playersheet), 1005 (scratchspace), 1008 (chatlog), 1006 (NPC tools),
  708 (the playerbots bridge), 1001 (voices), 1003 (the channel)

## Current Behavior

The world is empty by design and the bots that populate it have no interior.
mod-playerbots gives a companion a class, a level and a combat rotation; it does
not give it anything to think, and nothing it does accumulates into anything.

Neuron can move creatures, dress them, and remove them. It cannot make one
*live* anywhere.

## Intended Behavior

A creature that stays in one place, does things, remembers some of them, and
narrates its own life in the first person — continuously, whether or not anybody
is watching. When somebody arrives, it is already in the middle of something.

That last clause is the whole design. An NPC that begins existing when a player
looks at it is a vending machine. One that has been keeping a scratchspace and
writing to a sheet for three days has a Tuesday behind it, and the difference is
legible in the first sentence it says.

### The loop

```
   what is around me            the scratchspace, N slots, first person
        │
        ▼
   what I have kept             the playersheet, deliberately written
        │
        ▼
   what I do next               one NPC tool, chosen
        │
        ▼
   what I say about it          first-person narration into the channel
        │
        └──── writes a `done` entry, and the ring turns
```

Nothing in that loop is new work except the choosing and the saying. The other
three are issues 1000, 1005 and 1006, which is why this is the capstone rather
than the beginning.

### Its storyline is its own scratchspace, read in order

The narration engine does not maintain a plot. There is no state machine, no
quest chain, no story object that behavior is generated from. There is a ring of
atoms, and the ring has exactly three properties:

1. **Order.** They are in the sequence they happened.
2. **Ownership.** They all belong to one creature, so they share a viewpoint.
3. **Mixture.** `seen`, `done` and `said` are in the *same* ring, interleaved.

Those three are sufficient, because that is what a narrative is: a viewpoint, a
sequence, and both what happened to you and what you did about it. The ring is
therefore already a story. The narrator's whole job is to *say* it.

**The mixture is the load-bearing one.** Kept in separate logs, perception and
action would have to be correlated to narrate — something would have to work out
which act was a response to which observation, and that correlation is exactly
where a plot engine would have to live. Interleaved in one ring in real order,
the correlation is already present as adjacency:

```
    [7]  cherries in the glade east          seen
    [8]  player in green at the well         seen
    [9]  said hello back                     said
    [10] walked east                         done
```

Nobody recorded that the creature went east *because* of the cherries. Position
says it. **Adjacency substitutes for causality**, cheaply, and sometimes wrongly
— the creature may have gone east for its own reasons and the narration will
imply a connection that was not there. That is not a defect. It is what a person
telling you about their afternoon also does.

### The pressure supplies the arc

Because the ring is bounded and remembering costs an act, what is in it at any
moment is already a selection. A creature that noted the cherries and then spent
an act to `remember` them will still be talking about cherries next week; one
that let the atom fall off does not know it ever saw them. Continuity of theme
is not maintained by a flag somewhere — it is whatever survived.

So the two stores are the two timescales a story needs. The **sheet** supplies
*this is a creature who cares about cherries and knows where the barracks is*.
The **ring** supplies *and right now it is at the well, talking to you*. The
difference in duration between them is the difference between character and
incident, and it costs nothing to maintain because it is the same mechanism
running at two speeds.

### What follows from building it this way

- **There is no second representation to keep in sync.** The creature's state is
  the ring and the sheet. Nothing has to be saved that is not already the thing
  itself.
- **Two creatures in one room have two different stories about the same
  evening, for free.** Each has its own ring and made its own selections. No
  work produces the divergence; it is what separate viewpoints are.
- **A creature can be confidently wrong.** Narration is downstream of
  impressions, not of the world. It will say the door is open because the atom
  says so.
- **The narrator can be replaced without changing what the creature is.** The
  rendering is a translation of the acts, not a construction of them. A bad
  narrator produces poor prose about a real afternoon; a plot engine with a good
  renderer produces good prose about nothing.
- **There is no ending, and that is correct.** A plot has a climax. A ring has a
  next atom. Issue 1004's "narration that trails off" is not graceful
  degradation — it is the honest shape of the thing.

### Playing with people whenever they please

The creature is available. Not quest-giving, not vendoring — available. Somebody
walks up, says something, and the creature has a scratchspace with them in it
and a sheet with a Tuesday in it, and answers out of both.

Dynamic quests come later and are not this. This is a person to talk to.

## Suggested Implementation Steps

1. Stand one up doing nothing but existing: resident script, a sheet, a
   scratchspace, no tools. Confirm it survives a worldserver restart, because a
   creature whose Tuesday evaporates nightly is the vending machine again.
2. Give it the smallest tool set and a hand-written sequence. Read its
   scratchspace afterwards and see whether it reads as somebody's afternoon.
3. Write the narration pass: slots in, first-person sentences out.
4. Put narration in the channel (issue 1003) and watch it from a character
   standing nearby.
5. Only then connect a model to the choosing step. Everything above works
   without one, which is the same reasoning that put the levers before the
   asking and the window before the model.

## Open Questions

- **What does it do when nobody is there?** Narrating to an empty field is
  either the point — it has a life regardless — or it is burning a model's
  budget on nobody. Probably it acts and does not narrate, and narration begins
  when it has an audience. Unsettled.
- **How often does the loop turn?** Once a tick is a creature with no interior
  life at all, just twitch. Once a minute is a creature that misses somebody
  walking past. It likely varies with whether anybody is nearby, which makes it
  a second knob beside N.
- **What happens when it dies?** This is issue 1000's identity question arriving
  with consequences. A narrator that remembers dying is a very different thing
  from one that comes back new.
- **How many can exist at once?** Each is a resident script, a sheet, a ring,
  and — eventually — a model call. Twenty is a village. Twenty thousand is the
  bot fleet, and nothing about this design says what happens at that number.
- **Does narration write a `said` atom?** This is the sharpest question here.
  The voice is the creature's own and first person, so if narrating writes back
  into the ring, the creature reads its own narration next turn and begins
  responding to itself. That is either a feedback loop producing drivel, or it
  is the only mechanism on the table that would make something look like it has
  an inner life — a creature that thinks about what it just said. It cannot be
  both and the choice has to be deliberate, because the difference between them
  may only be visible after an hour of watching.

## Related

- Issue 1005 — the ring whose pressure gives this its character
- Issue 1006 — what it can actually do
- `notes/vision` — the model pulls levers; it does not write code. This creature
  is the same position applied to something standing inside the world.
