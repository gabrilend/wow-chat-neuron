# 040-relevance.lua

How much of a creature's attention each of its three memory stores gets right
now, and how that turns into whole lines of a fixed context budget.

Pure arithmetic. No world, no deployment, no clock of its own — `now` is always
passed in, so a test can move time without waiting for it.

## Functions

### `Relevance.chatlog(last_change, now, curve) -> 0..1 | nil, why`
The chatlog's share, decaying exponentially from the last line appended **in
either direction**. Refuses a `last_change` in the future, naming both readings,
because that means two different clocks are being compared and a creature that
believes it is mid-conversation with somebody who left is worse than one that
cooled early.

### `Relevance.weigh(state, now, curve) -> {chatlog, ring, sheet}`
All three at once. Only the chatlog moves.

### `Relevance.budget(weights, total) -> {chatlog, ring, sheet}`
Whole allocations summing **exactly** to the total, by largest remainder.

### `Relevance.describe(weights, allocation) -> string`
One line per store. The only window onto why a creature answered as it did — a
creature that ignored the cherries because it was mid-conversation looks
identical, from outside, to one that never saw them.

## Only one store has a clock

| Store | How it forgets |
|-------|----------------|
| chatlog | **cools** — relevance decays; nothing is deleted |
| scratchspace | **falls off** — new atoms push old ones out, by position |
| playersheet | **never** — until `forget` strikes one |

The ring and the sheet are constants and that is the point of them. A store that
cooled would be a store whose contents become less true with age, and neither
does: an atom on the ring is either still there or has fallen off, and an atom
on the sheet was chosen and stays chosen.

## The curve

`CURVE` — half-life 8s, resting 0.0, full 1.0. Tuning belongs in
`docs/balance-updates.md`.

Half-life rather than slope because it is the parameter a person can reason
about: *half gone in eight seconds* is a sentence about behaviour.

Exponential rather than linear because a straight line has a corner at the end —
relevance falling steadily and then abruptly nothing. A creature drifts out of a
conversation; it does not fall out of one.

At the default, out of a hundred lines of context:

| seconds since last word | chatlog | chat / ring / sheet |
|---|---|---|
| 0 | 100% | 51 / 31 / 18 |
| 8 | 50% | 35 / 41 / 24 |
| 30 | 7.4% | 7 / 59 / 34 |
| 60 | 0.6% | 0 / 63 / 37 |

## Why the split is a function and not three multiplications

Rounding three proportions independently does not sum to the total. Three shares
of 100 that are each 33.33 round to 99; each 33.34 rounds to 102. One wastes a
line, the other truncates the prompt — and a prompt truncated at the end loses
whatever was most recent, which is exactly the part that mattered. That failure
does not look like an arithmetic bug when it happens. It looks like a creature
that stopped noticing things.

Largest remainder: floor everything, then hand leftover units to whoever the
flooring cheated most. Deterministic, with the store name as tiebreak, so the
same split twice puts the spare unit in the same place.
