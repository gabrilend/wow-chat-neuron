# 700 — Mechanisms: One Shape for Four Hands

## Status
- Phase: 7 (The Toolbox) — the floor of it; numbered below the registry
- Blocked by: 107 (enums)
- Blocks: 701 (registry), 706 (tools), 1006 (NPC tools reach through these)

## Current Behavior

All four mechanisms are built and the routing table asserts its own
completeness at load. Cold and live are doorways onto `002-cold-hand.lua` and
`003-live-hand.lua`, neither of which changed. Resident is new and writes a
script into the profile's ALE directory, reads the bytes back, and asks the
world to reload. None does nothing, successfully.

Twenty-eight tests cover the routing shape, all of them without a deployment.
What cannot be tested that way is not pretended to be: no cold write has been
performed through a mechanism, and no resident script has ever been installed,
because no worldserver has been up during any session that touched this.

Two things resident cannot yet see, both stated in the file rather than
smoothed over. The reload command is `reload eluna`, unverified against this
deployment's ALE — a wrong one surfaces as a refusal carrying the server's own
words, not as silence. And whether an installed script *compiled* is invisible:
a syntax error installs perfectly and never runs, which looks exactly like the
feature not working.

`020-cli.lua` still reaches for its hands directly. Converting it is the
remaining step.

## Intended Behavior

A **mechanism** is one hand, wearing a shape all four share. The dispatcher
holds a table keyed on the hand enum member and never learns which one it got:

```
MECHANISMS[step.hand].perform(handle, step)
```

That is the routing issue 107 exists to make safe. One index. The key is a
member rather than a string, so a step carrying a hand that was never a real
hand was refused at the edge and never reached here.

### What every mechanism supplies

| Field | Type | Meaning |
|-------|------|---------|
| `hand` | enum member | Which one this is. Its own identity, not a name. |
| `probe(handle)` | function | up, reason, detail — already written for cold and live |
| `perform(handle, step)` | function | Do the step. Returns an outcome, never throws. |
| `describes(step)` | function | One line a person reads before agreeing to it |
| `carries` | array of string | Which step fields it needs: `sql`/`binds`, `command`, `script` |

`carries` is what lets a step be validated before anything is attempted. A cold
step with no `sql` and a live step with no `command` are both programming
mistakes in an operation, and they should surface when the plan is built rather
than halfway through applying it to forty characters.

### The four

**Cold** wraps the existing SQL hand. `perform` reads `step.sql` and
`step.binds`, picks the database from `step.database`, and returns the affected
row count. It changes nothing about how the cold hand works; it gives it a
uniform doorway.

**Live** wraps the existing SOAP hand. `perform` reads `step.command`. The
existing addressing table still gates it: a command addressed by selection
cannot be performed through SOAP at all, and that refusal belongs here, once,
rather than in each operation that might have reached for one.

**Resident** is new. `perform` writes `step.script` into the deployment's ALE
custom directory and asks the running worldserver to reload. It is the only
mechanism whose effect **outlives the call** — the script stays there and keeps
running on the server's tick. That difference is not a detail; it is why the
resident hand can hold a guard on a hill or a creature who keeps narrating,
and the other two cannot.

**None** performs nothing and is always up. It exists so that
`neuron.catalogue` and `neuron.explain` are ordinary operations routed the
ordinary way, rather than special cases the dispatcher has to check for. A
mechanism that does nothing is cheaper than a branch that means nothing.

### Outcomes, not exceptions

`perform` returns an outcome table: `done` with what changed, or `failed` with
a refusal kind from the enum and a sentence. It never raises. An operation
walking forty steps needs the thirty-ninth failing to be a value it can record
in a receipt, not something that unwinds the stack past the receipt writer.

## Suggested Implementation Steps

1. Write the shared shape as a constructor that refuses a mechanism missing any
   required field, so a half-written fourth hand fails at load rather than at
   the moment somebody routes to it.
2. Wrap cold and live without changing either file. They work and have been run
   against a live world; the wrapper is a doorway, not a rewrite.
3. Write resident: install a script, ask for a reload, verify it loaded. The
   verification matters — a script with a syntax error installs fine and simply
   never runs, which looks exactly like the feature not working.
4. Write none.
5. Build the dispatch table keyed on `Hands` members and assert at load that
   every member has a mechanism. A hand with no mechanism is a routing hole
   that only shows up when somebody declares an operation preferring it.
6. Convert `020-cli.lua`'s three commands to route through the table.

## Open Questions

- **How does a resident script get removed?** Installing is a file write.
  Removing is a file delete plus a reload, and a reload with the file gone may
  leave the previous version resident in memory. Untested, and the failure mode
  is a script you believe you deleted still running.
- **Does resident need its own probe?** It currently borrows `world_up`, since
  ALE lives in the worldserver. But a worldserver running with ALE disabled is
  up and cannot host a resident script at all, and nothing distinguishes those.
- **What is `step.database` for the live hand?** Nothing, and a step carrying it
  anyway is either harmless or a sign the operation is confused about which
  hand it is building for. Probably worth refusing.

## Related

- `docs/datapath-operation-dispatch.md` — steps 4 and 7, which this is
- Issue 107 — the hand enum this routes on
