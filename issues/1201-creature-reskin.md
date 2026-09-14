# 1201 — `creature.reskin`: Change What Something Looks Like

## Status
- Phase: 12 (Likeness)
- Blocked by: 1200 (what a model is), 109 (standing stubs), 700 (mechanisms)
- Blocks: 1205 ("change that goblin")

## Current Behavior

Nothing can change an appearance. A goblin is a goblin because a row says so,
and no word in the vocabulary touches that row.

## Intended Behavior

```
neuron reskin --creature 23825 --display 21854 --plan
```

Change which display a creature kind uses. **Works today, entirely, with no
client change**, because it only ever selects from the 21,381 displays the game
already ships.

### It is a stub, and says so

This is the prototype for something much larger: eventually the display should
be able to come from a converted asset somebody found on the web (issue 1203).
Until that exists, this picks from what shipped.

**That is not a fallback and it must not look like one.** It is the deliberate
placeholder that lets the asking, the plan, the confirmation and the receipt all
be built and driven before anybody writes a scraper. So it declares a stub
(issue 109), and every use of it says:

```
[ STUB ] choosing what a creature looks like
  doing        picking from the displays the game already ships
  instead of   finding art on open-game-art and converting it
  go build it  issues/1203-the-asset-scrapers.md
```

On the terminal the first time, in the plan a person agrees to, and in the
end-of-run summary with a count. Somebody who has never read this file finds out
anyway.

### Size travels with the look

`creature_model_info` holds each display's bounding radius and combat reach.
Changing the display without changing those makes a creature whose sword swings
from where its old body was — which does not error and does not look like a
bug, it looks like the game being janky.

So a reskin either carries the new display's own size row or refuses.

### Which hand

`{ cold }` for the template — future spawns look different immediately, and no
running creature changes.

Changing what is **standing there right now** is a different act: the client has
already been told what that creature looks like. It needs the creature
respawned, or a resident script morphing it in place. Stated as an open question
rather than assumed, because "the plan said it changed and nothing changed" is
the exact failure mode this project keeps designing against.

## Suggested Implementation Steps

1. Declare the stub at module scope so it is listed by `scripts/stubs` whether
   or not anybody runs a reskin.
2. Plan: read the current displays, resolve the new one, refuse a display with
   no `creature_model_info` row.
3. Put the stub's block in the plan description, above the steps.
4. Apply: write `creature_template_model`, capture the prior display into the
   receipt so it is reversible.
5. Test the reverse first. A reskin that cannot be undone is a world nobody
   wants to experiment in.

## Open Questions

- **Does it affect creatures already spawned?** Almost certainly not, and the
  plan must say so rather than let somebody discover it.
- **Should it take a name rather than a number?** `--display 21854` is not
  something a person can mean. But a name would have to come from somewhere, and
  the server has no names for displays.
- **What about scale?** `DisplayScale` makes a thing bigger without a new model,
  which is most of what "change that goblin" might mean and is far cheaper than
  new art.

## Related

- Issue 109 — standing stubs
- Issue 1203 — what this stands in for
