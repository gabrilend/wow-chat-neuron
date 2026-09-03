# 901 — The Browser Door

## Status
- Phase: 9 (The Doors)
- Blocked by: 101-106 (the hands), 201-205 (something worth asking for)
- Partially blocked by: 703 (tool schema), 802 (the conversation loop)

## Current Behavior

The only way in is a terminal. Everything the project can do is reachable, and
only by someone who knows the flag names.

## Intended Behavior

A chat window in a browser. You type what you want; the world changes; the window
tells you what happened.

It is served by a small HTTP server that neuron runs itself, on loopback,
against the same deployment handle every other part of the project uses.

### The window is a chat frame, not a form

The thing being talked to lives in a game, so the window should look like the
game's own chat rather than like a control panel. Dark, gold-edged, a scrollback
above and a single input line below. Messages are coloured the way the game
colours them: system text yellow, errors red, someone speaking in white.

This is not decoration. A control panel invites you to fill in fields; a chat
frame invites you to say something, and saying something is the entire interface
this project is aiming at.

### What it does before there is a model

The model is not required for the door to be useful, and building it that way is
deliberate — the same reasoning that put phases 1 to 6 before phase 8.

Typed text is matched against the **operation vocabulary** directly, forgivingly:
`who are the hunters`, `where is ratchet`, `move the hunters to ratchet`. These
are the same operations the command line exposes, reached by a friendlier
grammar.

That grammar is not a pretend model, and it is not a rival to one. It is the
**substrate** the model will write to. Issue 917 in the sibling project put it
exactly right: *the AI should write those commands, the player should just ask.*
Building the commands first, and making them speakable by hand, means the model
has something real to aim at rather than an interface invented for it.

Anything the grammar does not recognise is handed to the model. With no model
configured, the window says so plainly and names what it *can* understand,
rather than failing silently or guessing.

### Every change is shown before it is made

The window inherits the plan/apply split. A request that would change something
comes back as a plan first — the same sentences the terminal prints — with the
choice to run it or not.

This is the property that makes handing the same door to a model safe later. The
review step already exists and does not need adding when the model arrives.

### Loopback only

The server binds to `127.0.0.1` and nothing else, for the same reason the
deployment binds its game-master console there: this thing can empty a world,
and it authenticates nobody. A door that anyone on the network can open is a
different design with different requirements, and it is not this one.

## Suggested Implementation Steps

1. Write the HTTP server on luasocket, which is already present system-wide. It
   needs three routes and no framework: the page, the ask, and the apply.
2. Write the page as a single self-contained file — no external fonts, no CDN,
   nothing fetched. It has to work on a machine with no internet, because the
   game server it drives runs on one.
3. Write the chat grammar: a small ordered list of patterns, each mapping a
   phrasing onto an operation and its arguments. Keep it small and boring; it is
   a router, not a language.
4. Route unrecognised input to the model path, and have that path report clearly
   when no credentials are configured.
5. Return plans as structured results the page can render as a plan, with a
   confirm control, rather than as prose the page has to parse.
6. Keep a per-window scrollback so the conversation is legible, and make it
   survive a page reload.

## Open Questions

- **What happens when two windows are open?** Applies must serialise or two plans
  can contradict each other, which is issue 905's queue. Until that exists, a
  second window is a way to lose a change.
- **Should the window show the world?** A list of who is online, where they are.
  Useful, and the beginning of a control panel, which is what the chat frame is
  deliberately not.
- **How much history does a request carry?** "Now move her too" needs the
  previous exchange. Keeping everything is a context problem later.
- **Does the door need to authenticate anyone?** Loopback makes it moot today.
  The moment it is not loopback, it is the only question.

## Related

- Issue 905 — tabs, and why applies must serialise
- Issue 902 — the in-game door, which is the same loop through a different surface
- `../wow-chat-2026/issues/917-ask-the-bots-in-plain-text.md` — where "the AI
  writes the commands, the player just asks" was first written down
