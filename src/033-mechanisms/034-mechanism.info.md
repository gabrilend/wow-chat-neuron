# 034-mechanism.lua

One hand wearing a shape all four share, plus the table that routes to them.

Covers this file and the four mechanisms beside it.

## Functions

### `Mechanism.define(specification) -> mechanism`
Needs `hand` (a `Hands` member), `probe`, `perform`, `describes`. Anything
half-written is refused **at load**, so a fourth hand missing its `perform`
fails at startup rather than on the day somebody declares an operation
preferring it.

### `Mechanism.dispatch(neuron_root) -> table keyed by Hands member`
Builds the routing table and asserts every hand has an entry.

### `Mechanism.done(changed, detail)` / `Mechanism.failed(refusal, why)`
The two outcomes. `failed` requires a `Refusals` member, so a caller can branch
on the kind without reading the sentence.

## What a mechanism gives you

| | |
|---|---|
| `.hand` | which one this is, as a member |
| `.probe(handle)` | up, reason, detail |
| `.perform(handle, step)` | an outcome; **never raises** |
| `.describes(step)` | one line a person reads before agreeing |
| `.validate(step)` | true, or nil plus why |

## The routing

```
MECHANISMS[step.hand].perform(handle, step)
```

One index into a table keyed on enum members. Not a chain of comparisons, and
not keyed on a string that could be a near-miss spelling — a spelling that was
not a real hand was refused where text became a member and never reached here.

## Steps are validated against their own hand's needs

`validate` reads the required fields off the hand enum's `carries` list rather
than restating them, so *what a cold step needs* lives in one place. Presence is
the test, not truthiness — a statement with no placeholders binds an empty table
and that counts as given.

## Failures are values

Nothing raises. An operation walking forty steps needs the thirty-ninth failing
to be something it can write into a receipt, not something that unwinds the
stack past the receipt writer and leaves no record that thirty-eight succeeded.
A hand that raises anyway is caught and turned into a `refused` outcome carrying
the original error and the step's description.

## The four

| File | Hand | Notes |
|------|------|-------|
| `035-cold.lua` | cold | Doorway onto `002-cold-hand.lua`, unchanged. Zero affected rows is zero, not an error. |
| `036-live.lua` | live | Doorway onto `003-live-hand.lua`. Refuses selection-addressed commands **before sending**, since they would not error — they would act on nothing and report success. |
| `037-resident.lua` | resident | New. Writes a script into the profile's ALE directory, reads it back, asks the world to reload. |
| `038-none.lua` | none | Does nothing, always up. Keeps `neuron.catalogue` an ordinary operation instead of a branch. |

## Two things resident cannot yet see

**The reload command is unverified.** `reload eluna`, never run against this
deployment's ALE because no worldserver has been up. A wrong command surfaces as
a refusal carrying the server's own words, not as silence.

**Whether the script compiled.** A script with a syntax error installs fine and
never runs, which looks exactly like the feature not working. The write is
verified by reading the bytes back; the compile is not verified at all.
