# 051-loop.lua

A sentence in, a plan or an answer out. The middle of the pipeline, and the last
piece of it.

## Functions

### `Loop.ask(handle, registry, sentence, options) -> answer | nil, kind, why, partial`
`options`: `hold(plan, operation) -> id`, `filter`, `api`. Returns
`{ answer, plans, turns, calls, ended, note }`.

### `Loop.system_prompt(handle, registry) -> string`
### `Loop.level_cap(handle) -> cap, source | nil, why`

## The rule the safety model rests on

**Inside this loop, a change is planned and never applied.** When the model calls
a word that alters anything, the loop runs its `plan` and hands back the plan's
*description* as the tool result. So the model composes freely — twenty spawns, a
teleport — and what reaches the person is twenty readable lines and a question.

The apply happens afterwards, through the door's hold-and-confirm, which already
refuses to confirm the same plan twice. A model that could apply directly would
be one that could finish before anybody read what it was doing.

**Reads run immediately**, because there is nothing to agree to. That asymmetry
is what makes *"successive undead encounters, level progressing"* possible: the
model has to **look** several times while composing, and asking permission to
look would make it unusable.

That is the `kind` enum doing real work — `read` and `change` take different
paths, decided by data on the declaration rather than by a list of exceptions
kept somewhere else.

## The level cap is read, never assumed

`MaxPlayerLevel` out of the profile's own `worldserver.conf`. **There is no
fallback.** When no such file exists — the `neuron` profile is databases with no
installed server — the prompt does not assert a cap; it says the cap is unknown
and very likely not 80.

It was briefly a table of profile names to numbers, which was wrong twice: the
active profile was not in it, and the lookup fell through to 80. That produced
*"the maximum character level is 80, not 80"* and, worse, a confident false
claim. A model that thinks the cap is 80 on a level-40 world builds encounters
nobody can reach.

## Every tool_use gets a tool_result

Including the failures. A missing one is rejected outright by the API, and it is
easy to produce by returning early on the first failure. A failed operation comes
back with `is_error` and the refusal text — which is what the four-kind refusal
vocabulary was kept small for.

The assistant turn goes back **verbatim**. Reconstructing it risks losing a
`tool_use` id.

## Plans go to the caller's store

`options.hold` lets the door supply its own, so a plan the model proposed is
confirmed through exactly the same path as one the hand-matched vocabulary
proposed. Two stores would be two ways to run a plan and eventually two answers
about whether one had already run.

## The transport is a seam

`options.api` — so the loop is driven against a scripted responder with no
network and no key. Everything interesting here is the shape of a conversation.

## The turn cap

`config/asking.lua`'s `max_turns`. Reaching it means the model kept calling tools
without finishing — usually a read, a refusal, and the same read again. It says
so, and lists every call, rather than silently returning the last partial answer.
