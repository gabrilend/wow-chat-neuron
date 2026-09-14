# 802 — The Conversation Loop

## Status
- Phase: 8 (The Voice)
- Blocked by: 801 (the transport), 703 (the tool schema), 701 (the registry)
- Blocks: nothing — this is the last piece of the MVP

## Current Behavior

**Built.** `src/051-loop.lua`, wired into `022-http-server.lua` — the chat
window's fallthrough now goes to a model instead of refusing.

Driven end to end against a scripted responder: thirty-three tests covering the
read/change split, `tool_result` id matching across a three-call turn, the turn
cap, and a failure part-way through keeping what was already said. No live model
has answered, because no key is configured.

Three things changed while building it.

The loop originally re-loaded each operation's file to reach its `plan` and
`apply`. The registry already holds those functions, so that was a second route
to the same code — one that can disagree with the first the moment a registry
entry is built any way but from a file. It now calls them off the entry, and
`022-http-server.lua`'s apply path does too, which also removed a hardcoded
two-operation map from a file that has nothing to do with operations.

The level cap was a table of profile names to numbers. The active profile here is
`neuron`, which was not in it, so the lookup fell through to 80 and produced the
sentence *"the maximum character level is 80, not 80"* — and, much worse, a
confident claim that happened to be false. It now reads `MaxPlayerLevel` from the
profile's own `worldserver.conf`, and when there is no such file (which the
`neuron` profile genuinely has, being databases with no installed server) it does
not assert a cap at all. It tells the model the cap is unknown and very likely
not 80.

The transport became an injectable seam, so the loop can be driven with no
network and no key. Everything interesting here is the shape of a conversation,
and none of it should need an API to exercise.
## Intended Behavior

A sentence in, a plan or an answer out.

```
   sentence
      │
      ▼
   messages = [ { role = "user", content = sentence } ]
      │
      ▼
 ┌──► send: messages + tools + system
 │       │
 │       ▼
 │    stop_reason?
 │       │
 │       ├── "end_turn"  ──► the text is the answer. done.
 │       │
 │       └── "tool_use"  ──► route each block to its operation
 │                             READ  -> run it, result is the answer
 │                             CHANGE -> plan it, hold the plan,
 │                                       result is the plan's description
 │              │
 │              ▼
 └────── append assistant turn + tool_result blocks
```

### A change is planned, never applied, inside the loop

This is the rule the whole safety model rests on. When the model calls a word
that changes something, the loop runs its **plan** and returns the plan's
description as the tool result. Nothing is applied.

So the model can compose freely — twenty spawns, a teleport, a level change —
and what comes back to the person is twenty readable lines and a question. The
apply happens only after a person agrees, through the door's existing
hold-and-confirm, which already works and already refuses to confirm the same
plan twice.

A model that could apply directly would be a model that could finish before
anybody read what it was doing.

### Reads run immediately

`world.creatures` changes nothing, so there is nothing to agree to. It runs, and
its rows come back as the tool result, and the model uses them to choose the
next thing. That asymmetry is what lets a request like *successive undead
encounters, level progressing* work at all: the model has to be able to **look**
several times while composing, and stopping to ask permission to look would
make the whole thing unusable.

This is the `kind` enum doing its work — `read` and `change` take different
paths through the loop, decided by data on the declaration rather than by a list
of exceptions.

### Every tool result must come back

An assistant turn containing three `tool_use` blocks must be answered by a user
turn containing three `tool_result` blocks with matching ids. A missing one is
rejected, and it is easy to produce by returning early on the first failure. A
failed operation returns a `tool_result` with `is_error` set and the refusal
text — which is what the four-kind refusal vocabulary was kept small for.

### The turn limit is a real limit

A model that loops — calling a read, getting a refusal, calling it again — has
to stop. A cap on turns per sentence, and when it is hit, say plainly that it
was hit and show what happened up to that point. Silently returning the last
partial answer is how somebody believes a thing finished.

## Suggested Implementation Steps

1. One turn, no tools. Prove the transport and the decode.
2. One turn with tools and one read. Prove routing works in both directions.
3. Add the change path: plan, hold, describe. Prove nothing is applied.
4. Add multi-block turns and the id matching. This is where the bugs are.
5. Add the turn cap and the loop-detection message.
6. Wire `021-chat-router.lua`'s fallthrough to this instead of refusing.

## Open Questions

- **What is in the system prompt?** Issue 803. At minimum: which world this is,
  what the level cap is, that the world is empty by design. A model that does
  not know the max level is 40 will build an encounter chain to 80.
- **Does the model see the plan it just made?** If the tool result is the plan's
  description, the model can read its own proposal and revise it — which is
  useful and also how it talks itself into a longer plan than anybody wanted.
- **How does a held plan get named?** Twenty spawns as twenty held plans is
  twenty confirmations. One plan of twenty steps is one, and the loop has to
  merge across tool calls to get there.
- **What happens when the person says no?** The plan is thrown away, and the
  model is either told and can offer something else, or is not and the
  conversation ends.

## Related

- Issue 901 — the door, whose hold-and-confirm this reuses unchanged
- Issue 804 — approval gates, of which this implements the strictest form
