# 701 — The Operation Registry

## Status
- Phase: 7 (The Toolbox)
- Blocked by: 107 (enums), 700 (mechanisms)
- Blocks: 702 (CLI generation), 703 (tool schema), 705 (catalogue), 802 (the loop)

## Current Behavior

**Built.** `src/045-toolbox/047-registry.lua`, with `046-types.lua` beside it for
the parameter-type enum. The three existing operations register and validate.

Before it, an operation was reachable only because `020-cli.lua` had a function
that knew about it — seven hand-written subcommands, each importing its file and
calling plan and apply in that operation's own idiom. Nothing could enumerate
them, so nothing could print the set, hand it to a model, or refuse an unknown
name with a list of the real ones.

`020-cli.lua` still has those seven functions. Converting it is issue 702.

## Intended Behavior

One table, keyed by name, holding every word neuron knows. A dispatch table —
one hash index to find a word, not a walk down a chain of comparisons — and the
only object in the project that can answer *what can this thing do*, which is
the question every other surface is built out of.

### Validation is harsh and happens at load

An operation half-declared is found when the registry is built, once, at
startup. The alternative is finding it the first time somebody asks for that
word, which is later, further from the mistake, and quite possibly in front of a
model that will now try something else instead.

Refused, each with a message saying what the rule is for:

| | Why it would produce a bad word |
|---|---|
| a name that is not `subject.verb` | sorting by subject is how somebody finds a word they half-know |
| an unknown hand or parameter type | it would route nowhere, or coerce as nothing |
| no hands at all | an operation touching nothing declares `none`, so the dispatcher has no special case |
| a `change` with no `apply`, a `read` with no `run` | the kind says which functions must exist; that is what makes it a switch |
| a summary or parameter description too short to teach | prose is the only thing a model has when choosing |
| anything `final` with no `confirm` | the gate is the parameter's presence in the schema |
| anything `final` whose `confirm` is **required** | a required confirmation is filled with `true` on the first attempt, and the gate becomes decorative |

### The refusal for an unknown word is a feature

A name that is not in the registry ends that request. So the refusal carries
what *would* have worked: first the other words about the same subject, then the
whole set. For a person that is a convenience. For a model it is the only thing
telling it what exists.

### Operation files are listed, not discovered

A directory scan makes the vocabulary depend on what happens to be lying in a
folder, and a half-finished operation dropped in during a refactor would join it
silently.

## Suggested Implementation Steps

1. Convert hands and kinds from strings to enum members at define time. That is
   the boundary; inward of it everything compares by identity.
2. Refuse at the first bad word rather than collecting problems. A registry that
   half-loaded is a vocabulary nobody can reason about.
3. Build `usage` from the declaration — flags from parameter names, brackets from
   required, and `--plan` added by kind rather than declared by each operation.
4. Sort by name, which sorts by subject, which groups every word touching a
   character together.

## Open Questions

- **Does coercion belong here?** Issue 704. Today each operation resolves its own
  roster and place inside `plan`. Moving that into the registry means every
  operation resolves identically and a bad roster is refused before any plan
  runs; it also means editing three working operations.
- **Should reads be registered before they have declarations?** The four
  read-only CLI commands have none, so the registry holds three words where the
  vocabulary sketch has forty-two. A model can act on the world and cannot look
  at it.
