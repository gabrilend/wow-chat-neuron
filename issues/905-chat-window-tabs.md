# 905 — Tabs in the Chat Window

## Status
- Phase: 9 (The Doors)
- Blocked by: 901 (the browser door)

## Current Behavior

The browser door, as designed in issue 901, is one window holding one
conversation. A request runs to completion before another can start.

## Intended Behavior

> the chat window should have tabs built in so multiple things can be worked on
> at once. Using the same system we use, steadily resolving things one-by-one.

Several pieces of work open at the same time, each in its own tab, each with its
own conversation and its own state — and **resolved one at a time**, in order,
not raced against each other.

The second half of that sentence is the design, and it is easy to miss. Tabs
here are not parallelism. They are a **queue you can see**. You open work,
you switch between it freely, you watch its state — and underneath, one thing
is being resolved at a time, steadily, the way this project resolves an issue
file at a time rather than starting six.

That is the same discipline the project already runs on, given a window.

### A tab's state

| State | Means |
|-------|-------|
| `drafting` | You are typing. Nothing has been asked yet. |
| `waiting` | Asked, and behind other work in the queue. |
| `thinking` | The model is choosing operations for this tab now. |
| `holding` | A plan is ready and needs your approval before it applies. |
| `applying` | Operations are running. |
| `settled` | Done. The receipt is attached to the tab. |
| `refused` | It could not be done. The reason is in the tab. |

`holding` is the state that makes tabs worth having. A plan that needs a human
yes should not block every other piece of work while it waits for one — so it
holds, the queue moves on, and you come back to it.

### One at a time, and why

Two plans applying at once can contradict each other. One tab moves the party
to the docks while another re-equips them; both succeed, and the result is
whichever finished last, with no error anywhere.

Serialising the *apply* step removes that entirely. Planning can overlap freely
— it is pure and reads only — but applies go through one at a time, in order.

## Suggested Implementation Steps

1. Give each tab a conversation of its own: its own message history, its own
   accumulated tool results. Tabs must not share context, or a request in one
   will silently answer with facts from another.
2. Write the queue: tabs enter it when asked, leave it when settled or refused,
   and exactly one holds the apply lock at a time.
3. Write the state machine above, with the transitions as a dispatch table
   rather than a chain of conditions.
4. Make `holding` non-blocking: a tab awaiting approval releases the lock and
   re-enters the queue when answered.
5. Show the queue position in each waiting tab. "Third in line" is the
   difference between patience and suspicion that it has hung.
6. Persist tabs across a page reload. Work that vanishes when a browser refreshes
   is work nobody will trust the window with.

## Open Questions

- **Does a tab survive a neuron restart?** Persisting the conversation makes the
  window durable and makes stale plans possible — a plan computed before the
  restart may describe a world that no longer exists.
- **Can a tab be re-run?** Re-asking the same request against a changed world is
  a plausible thing to want and is very close to what a queststorydungeon does,
  which suggests the two features should be looked at together.
- **What happens to queued tabs when one fails?** Continuing is probably right,
  since tabs are independent by construction, but "probably" is not an answer
  when the failed one was a prerequisite somebody held in their head.

## Related

- Issue 901 — the browser door
- Issue 804 — approval gates, which is what `holding` is waiting on
- Issue 1101 — the queststorydungeon, which is a settled tab made portable
