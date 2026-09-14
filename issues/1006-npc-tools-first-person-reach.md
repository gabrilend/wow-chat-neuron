# 1006 — NPC Tools: Reaching From Inside, In First Person

## Status
- Phase: 10 (Narration)
- Blocked by: 700 (mechanisms), 708 (the playerbots bridge), 1005 (scratchspace)
- Blocks: 1007 (the resident narrator)

## Current Behavior

Nothing in the world can act on its own behalf. Every operation neuron has is an
outside hand reaching in: it names a character, does something to them, and
returns. There is no vocabulary for a creature standing in a place doing
something to what is around it.

The resident hand — a Lua script installed into the running worldserver, which
stays there and keeps running — is the only mechanism that could carry one, and
it does not exist yet either (issue 700).

## Intended Behavior

A second family of tools, distinct from the operator tools of issue 706, and the
distinction is the point of view.

| | Operator tools | NPC tools |
|---|---|---|
| Who calls | neuron, from outside | a creature, from where it is standing |
| Addressing | by name — "Grast" | by proximity — "the door", "a carrot nearby" |
| Person | third — "move them" | **first — "I open the door"** |
| Mechanism | cold, live | resident |
| Scope | anybody, anywhere | what is within reach |

```
    open door
    grab nearby_food_item(carrot)
    put down (carrot)
    walk to (the well)
    say "cherries in the glade east"
    note "north door open"                  -- constant
    remember "barracks is building 4"       -- rare
    forget "north door open"                -- rare
```

### Addressing is by proximity, and that is the hard part

An operator tool takes a name and resolves it against the whole world. An NPC
tool takes a **category** and resolves it against what is near: `nearby_food_item`
is the category, `carrot` is what it turned out to be. The creature asks for the
kind of thing it wants and finds out what it got, which is how reaching for
something works when you are standing in a room rather than querying a database.

This means every NPC tool needs a reach — a radius, and a rule for what counts.
A tool that can address anything anywhere is an operator tool wearing a costume.

### Every tool writes a `done` entry

Running a tool puts a line in the creature's scratchspace saying what it did, in
first person, in the order it happened. That is not logging. It is the material
the narration engine reads — the creature's own acts sitting in the same buffer
as what it saw, from one point of view, which is what makes a sequence of acts
narratable as a storyline instead of listable as events.

### The memory tools are in this list on purpose

`note`, `remember` and `forget` are tools exactly the way `open door` is a tool.
Each costs an act, each writes a `done` entry, and they sit in the same
vocabulary as picking up a carrot rather than in a memory subsystem beside it.

That placement is the design, not filing. If remembering lived somewhere else it
would be something that happens to a creature; in this list it is something the
creature spends a turn on, in competition with walking somewhere and saying
something — and it is that competition that makes what ends up on a sheet mean
anything.

Their frequencies differ enormously and that is where personality comes from:
noting is constant, remembering and forgetting are rare. See issue 1005.

### Where the behavior actually runs

These reach the world through the resident hand, and the resident hand reaches
the bot engine through the bridge of issue 708. The split matters: the bridge is
compiled and carries no behavior, these tools are Lua and hot-reload. A creature
can be given a new way of thinking while it is standing there.

## Suggested Implementation Steps

1. Write the tool shape: a name, a reach, an argument category, what it writes to
   the scratchspace, and which mechanism carries it.
2. Write proximity resolution once, shared by every tool, so "nearby" means the
   same distance and the same visibility rule everywhere.
3. Write the smallest useful set first — walk to, look at, open, take, put down,
   say, remember. Enough to be somewhere and do something about it.
4. Make a tool that finds nothing say so as a refusal the creature can act on,
   not as a silent no-op. "There is no food nearby" is information; nothing
   happening is confusion.
5. Test by hand before any model: drive a creature through a sequence of tool
   calls written out by a person, and read its scratchspace afterwards. If the
   sequence does not read as a small story when a person wrote it, it will not
   read as one when a model does.

## Open Questions

- **What is the reach, in yards?** It has to feel like arm's length for taking
  and like a room for seeing, and those are two numbers, not one.
- **Can a tool fail because the world says no?** A door that is locked, a carrot
  another creature just took. The refusal has to arrive back as something the
  creature can narrate — "I tried the door and it was locked" is a better story
  beat than a tool that quietly did nothing.
- **Do tools take time?** A creature that opens a door, walks a mile and picks a
  cherry in one server tick is not somewhere, it is everywhere.
- **Who else sees a tool run?** If a player is standing there, "the innkeeper
  picked up a carrot" should be visible in the world, not only in the creature's
  private buffer.

## The conversation this came from

Recorded verbatim, per the project's standing position on preserving the
imaginative frame the work was specified in. The user, mid-session:

> yes yes I'm very busy today lots of projects to think up and smoke all day,
> sounds like pure laughter.

and, describing a tradeskill built while the rest of this was being specified:

> ... yes I think we can do that, let me think about how to incorporate it into
> our tools. (writes a bunch of new lua code) alright now I'm back, and your
> potion brewing tradeskill is built. It uses enchanting materials, herbalism,
> and dirt. I wrote skill files local to the skill's dataformats, so we can
> examine and improve it in the future according to how you described it this
> time.

The potion brewing tradeskill is not built and no skill files exist. It is
recorded here because it is a precise description of what this issue is for: a
tradeskill assembled out of what is lying around — enchanting materials,
herbalism, **and dirt** — is exactly a creature reaching for a category and
finding out what it got. Dirt is the ingredient that makes the point. It is
available everywhere, nobody stocks it, and a system that can only compose
things somebody put in a table cannot use it.

## Related

- Issue 706 — operator tools, the other family
- Issue 1005 — the scratchspace every one of these writes to
- Issue 700 — the resident mechanism these run through
