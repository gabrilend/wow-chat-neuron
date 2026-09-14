# 703 — The Tool Schema

## Status
- Phase: 7 (The Toolbox)
- Blocked by: 701 (registry)
- Blocks: 802 (the conversation loop)

## Current Behavior

**Built.** `src/045-toolbox/048-schema.lua`. The registry renders to a JSON
Schema tool list, and a `tool_use` block routes back to an operation.

Nothing consumes it yet, because nothing talks to a model (issue 801).

## Intended Behavior

The registry, rendered as a tool list. Nothing hand-written, and no second
description of an operation anywhere — every field comes off the declaration
that already serves the command line. That is what makes the project's standing
rule true rather than aspirational: **an operation cannot exist as a command
without existing as a tool.**

### The collapse that makes one declaration serve both surfaces

The four resolving parameter types — roster, place, items, receipt — all become
`"type": "string"`. A model cannot hold a resolved roster and should not try; it
says the words a person would say, and coercion turns them into rows on the way
in.

Which means the **prose attached to each parameter is carrying all of the
teaching**, and is why the registry refuses a description too short to say
anything.

### The name changes by exactly one substitution

`character.teleport` becomes `character_teleport`, because API tool names are
letters, digits and underscores. Applied in one place, reversed in one place,
and written down — a mapping that lives only in code is one somebody
reimplements slightly differently.

### The description carries what a schema cannot

Two things a model must know before choosing a word, neither expressible as a
property of an argument: whether it can be undone, and what has to be running
for it to work. An irreversible word says so in capitals and says to get
agreement first.

### Filters remove a word rather than forbid it

`Schema.tools(registry, filter)` is how a conversation is given less than the
whole vocabulary. `no_final` hands over a list where the irreversible word is
simply **absent**.

That is a much stronger guarantee than instructing a model not to use something.
A tool that is not in the list cannot be called by mistake, by
misunderstanding, or by persuasion. The posture is expressed by what is handed
over rather than by what is asked for.

## Suggested Implementation Steps

1. Render one operation, then the set. The set is the easy half.
2. Keep the description as the declaration's own prose. Appending the type's
   `accepts` text was tried and produced the same sentence twice — that text
   belongs to the catalogue and the command line, where nobody wrote prose.
3. Write `route` alongside, so the round trip exists from the start: a tool call
   comes back as an operation and its arguments, with a missing required
   argument caught before the operation runs and the message repeating the
   description the model already had.
4. Encode an empty tool list as `[]`. An empty Lua table is both an empty list
   and an empty object, and a request carrying `{}` where an array belongs is
   rejected rather than read as "no tools".

## Open Questions

- **Should the whole set ever be handed over at once?** Forty-two words is a lot
  of prompt. Handing over the words about the subject somebody is talking about
  is cheaper and is a guess about intent.
- **How does a `list` parameter describe its items?** Currently `{"type":
  "string"}`, which is a claim nobody checked.
- **Does the model see receipts?** A word that returns a receipt id is only
  useful if it can pass that id to `character.return`, which means receipt ids
  have to survive in the conversation.
