# Phase 9 — The Doors: Progress

**Effect: asking works from inside the game.**

## Where it stands

| Issue | Title | Status |
|-------|-------|--------|
| 901 | The browser door | Built and driven end to end |
| 902 | The in-game door | Not started |
| 903 | Attribution | Not started |
| 904 | Backgrounding | Not started |
| 905 | Tabs | Blueprinted; one tab exists as a placeholder |

Run it with `scripts/neuron-chat`, then open `http://127.0.0.1:7879`.

## What works

Ask → plan → confirm → done, verified against the live world: two companions
moved to a port town through the window, then put back through the same window,
landing on their original ground. Confirming the same plan twice is refused.

The window arrived **before** the model, deliberately — the same reasoning that
put the levers before the asking. Typed text is matched against the operation
vocabulary directly: `who are the hunters`, `where is ratchet`,
`move the hunters to ratchet`. Anything unrecognised is handed to a model, and
with no model configured the window says so plainly and lists what it *does*
understand.

That grammar is not a pretend model. It is the substrate a model writes to. The
sibling project put it exactly right — the AI should write the commands, the
player should just ask — and building the commands first means a model has
something real to aim at rather than an interface invented for it.

## The journey

**Plans are held rather than recomputed.** A request that would change something
comes back as a plan and stays on the server, keyed by id. Confirming runs
exactly what was shown; planning again could produce something different. The
held plan is removed as it runs, whatever the outcome, because a plan describes
the world at one moment and one that could run twice is how somebody moves a
party to the docks twice and wonders why the second attempt did nothing.

**Class colour was the one piece of formatting worth returning data for.** The
roster answer sends the characters as structured data rather than rendered
lines, so each name is drawn in the colour the game uses for its class. Every
WoW player reads those without thinking, which makes them the cheapest meaning
available — a list of names becomes a list of roles at a glance. Flattening that
into a string would have thrown away understanding the reader already has.

**Query strings broke every route.** The request target carries the query with
it, so `/` and `/?ask=hello` arrive as different strings, and comparing the whole
target against a route made every parameterised link a 404. Found by adding
linkable questions and watching the page return "no such thing here". The fix is
correct HTTP handling regardless of the feature that exposed it.

**A pattern that killed its own shell.** Stopping the server with a process
match on its filename matched the shell running the command, because the pattern
appeared in that shell's own command line. Twice. Looking the process up by the
port it holds is both correct and immune to that.

**The profile became a per-run argument.** Testing the plan flow needed a world
with characters in it, and the obvious route was editing the config and editing
it back. Instead the window takes `--profile`, which is genuinely useful — one
window pointed at one world, another at another — and removes the whole class of
"forgot to change it back".

## Open questions carried forward

From issue 901: two windows open at once can contradict each other, because
applies do not yet serialise — that is issue 905's queue, and until it exists a
second window is a way to lose a change. Also whether the window should show the
world as well as talk about it, which is the beginning of the control panel the
chat frame is deliberately not.

The larger one: the window is the door, and there is still nothing behind it but
a pattern list. Free language needs phase 7's tool schema and phase 8's
conversation loop, and neither exists. The window will not change when they
arrive — it already sends a sentence and renders whatever comes back — which is
the point of having built it this way round.
