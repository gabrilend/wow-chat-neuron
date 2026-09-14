# 708 — The Playerbots Bridge: A Patch That Carries No Behavior

## Status
- Phase: 7 (The Toolbox) — a mechanism concern, not a narration one
- Blocked by: 700 (mechanisms — this extends the resident hand's reach)
- Blocks: 1006 (NPC tools), 1007 (the resident narrator)

## Current Behavior

The resident hand can install a Lua script into the worldserver and ask ALE to
load it. What that script can then *do* is whatever ALE already exposes, and ALE
exposes the core's own object model — players, creatures, gameobjects, maps.

It does not expose mod-playerbots. A bot in this deployment is driven by its
own engine, which lives in the module and is invisible from Lua:

| In the module | What it is |
|---------------|------------|
| `Bot/Engine/Action/Action.h` | the base class. `Execute(Event)`, `isUseful()`, `isPossible()` |
| `Bot/Engine/Strategy/Strategy.h` | what supplies triggers and the actions they reach for |
| `Bot/Engine/AiObjectContext.*` | the named-object registry actions are looked up in |
| `Bot/Engine/BuildSharedActionContexts.cpp` | where actions get their names |
| `Bot/Engine/Engine.cpp` | the loop that picks one and runs it |

So a creature can be moved, dressed and spawned from outside, and cannot be made
to *decide* anything. Every NPC tool of issue 1006 — open a door, take a nearby
carrot, walk to the well — is a decision followed by an action, and there is
currently no seam between the two.

## Intended Behavior

A patch against mod-playerbots, applied and reverted by the deployment's
existing `patches/B*.sh` system, which exposes the engine to Lua.

**The patch carries a bridge and no behavior.** This is the whole design
constraint and it is worth stating before anything else:

- A patch carrying *behavior* has to be edited, re-applied and recompiled every
  time an NPC changes its mind about anything. Deciding a creature should prefer
  fruit over bread becomes a build.
- A patch carrying a *bridge* is written once. The behavior lives in resident
  Lua, which hot-reloads, and a creature's mind can be changed while it is
  standing there.

The compiled half should therefore be as thin as it can be and still be a seam:
register one action that asks Lua what to do, and one strategy that reaches for
it. Everything about *what* to do is on the other side.

### The shape of the seam

```
   mod-playerbots Engine        picks an action, as it already does
        │
        ▼
   NeuronDeferredAction         one C++ Action, registered by name
        │  isUseful()           asks Lua: does this creature have a mind?
        │  Execute(event)       asks Lua: what does it do now?
        ▼
   ALE / resident Lua           the scratchspace, the sheet, the tools
        │
        ▼
   returns one tool call        which the C++ side performs through the
                                module's own action vocabulary
```

Two calls across the boundary and nothing else. `isUseful` is the cheap one and
runs constantly; `Execute` is the expensive one and runs when the engine has
chosen this action over the bot's ordinary ones.

### Why this is the right use of the patch system

The deployment's position is that cloned source is a regenerable build artifact
and customisations are reversible scripts that re-derive on every build. That
position holds only if the customisations are small and stable. A bridge is
both. A behavior tree is neither, which is precisely why it belongs on the Lua
side of the seam rather than in the patch.

The twenty-odd `B*.sh` patches already in the deployment are almost entirely
compile fixes and small hooks. This is the same kind of thing: one hook, in one
place, that makes a much larger thing possible somewhere else.

## Suggested Implementation Steps

1. Read the deployment's `upstream-patch-system` skill before writing any of
   this. Its apply/unapply, idempotency and marker conventions are what keep the
   round-trip to upstream clean, and a patch that does not follow them breaks
   every subsequent build rather than only this feature.
2. Find how ALE is reached from inside the module — whether the Lua state is
   accessible from an Action, or whether the call has to go through a queue the
   world thread drains. That answer decides everything about the shape.
3. Write the smallest possible action: one that asks Lua for a string and does
   nothing with it. Prove the boundary is crossable before crossing it with
   anything real.
4. Register it in the shared action context, and write the strategy that
   reaches for it.
5. Only then give it a vocabulary — the NPC tools of issue 1006.
6. Write the unapply and prove the tree round-trips to upstream HEAD clean, in
   the same session. A patch whose unapply is written later is a patch whose
   unapply is written wrong.

## Open Questions

- **Can Lua be called from a bot's action at all, on the world thread?** ALE runs
  in the worldserver, and so does the bot engine, but "in the same process" is
  not "on the same thread" and a Lua state touched from two threads is a crash
  rather than a bug. If the answer is no, the seam becomes a queue and every
  decision gains a tick of latency, which changes what a creature can react to.
- **What does `isUseful` cost?** It runs constantly, for every bot, on the
  server's tick. If answering it means entering Lua, the cost is multiplied by
  the size of the bot fleet — which this deployment holds between 128 and 256.
- **Does a bot with a mind still keep its ordinary strategies?** A creature that
  narrates its afternoon and also fights correctly is one thing; a creature whose
  every decision goes through the bridge is much slower and much stranger.
  Probably the bridge is one more strategy among the existing ones rather than a
  replacement for them.
- **What happens on unapply, to creatures that were ghosts?** Reverting the patch
  removes the seam. The sheets survive because they are neuron's, the behavior
  stops because it was the module's, and a ghost with no way to act is a state
  nothing currently describes.

## Related

- Issue 1006 — the NPC tools this makes reachable
- Issue 700 — the resident mechanism, which installs the Lua half
- The deployment's `patches/` directory and `upstream-patch-system` skill
