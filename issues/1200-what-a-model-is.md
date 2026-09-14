# 1200 — What a Model Actually Is, and Where the Wall Is

## Status
- Phase: 12 (Likeness) — the foundation of it
- Blocked by: 101 (deployment handle), 102 (the cold hand)
- Blocks: 1201 (reskin), 1204 (crossing the wall)

## Current Behavior

Nothing in neuron knows what anything looks like. `world.creatures` returns
names, levels, types and ranks — every fact about a creature except the only one
a person standing in front of it actually perceives.

## Intended Behavior

Read appearance, so it can be changed.

### Three tables and one number

A creature's look is a **display id**. The server holds no art at all; it holds
that number and hands it to the client.

| Table | Holds |
|-------|-------|
| `creature_template_model` | `CreatureID` → `CreatureDisplayID`, plus `DisplayScale` and `Probability` |
| `creature_model_info` | `DisplayID` → bounding radius, combat reach, gender |
| **the client's `CreatureDisplayInfo.dbc`** | `DisplayID` → the actual model files |

`Probability` is worth noticing: a creature can carry several displays and pick
between them per spawn, which is why two of the same kind can look different.

`creature_model_info` is the server's half — how big the thing is for collision
and reach. **Changing a display without changing that row makes a creature whose
sword swings from where its old body was.**

### The wall

**The client owns the art.** The server sends a number; the client looks it up
in a DBC it shipped with and loads model files out of its own archives.

A display id the client does not know renders as nothing, or as a fallback
placeholder. So:

| | Needs |
|---|---|
| reskin using a display the game already ships | **nothing** — a database write |
| any new art at all | a client patch archive **every player installs**, plus new DBC rows |

That is the wall this whole phase runs into, and it is worth knowing before any
of it is designed. **21,381 distinct display ids already ship** in this
deployment — an enormous palette on the near side, and a completely different
deployment story on the far side.

Everything in issues 1201 and 1205 lives on the near side and works today.
Everything in 1203 and 1204 has to cross.

## Suggested Implementation Steps

1. Read a creature's displays: `world.appearance`, a read, cold hand.
2. Return the scale and probability too — a creature with three displays is a
   creature that looks different each time, and a caller that sees only the
   first will be confused by its own results.
3. Join `creature_model_info` so the answer carries size, since size is what a
   reskin has to keep consistent.
4. Do **not** try to name what a display looks like. The server cannot know;
   that knowledge is in the client's archives and in a person's memory.

## Open Questions

- **How does anybody know what a display id looks like?** 21,381 numbers with no
  descriptions. A person who wants "something like a wolf but bigger" has no way
  to search. This is the question that decides whether the near side is usable
  at all, and the honest answers are all some form of *look at it* — which is
  what phase 10's cameras are for.
- **Does changing a display break anything that referenced the old size?** Combat
  reach and bounding radius are used by pathfinding and by melee range.
- **Is `Probability` per spawn or per look?** If per spawn, a reskin applies to
  future spawns and not to the creature standing there.

## Related

- Issue 1201 — reskinning with what already ships
- Issue 1204 — what it takes to add art that does not
