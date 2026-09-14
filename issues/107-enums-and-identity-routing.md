# 107 — Enums: Routing by Knowing Which One Was Ours

## Status
- Phase: 1 (Reach) — foundational; everything above imports it
- Blocked by: nothing
- Blocks: 700 (mechanisms), 701 (registry), 706 (tools), 1000 (the playersheet)

## Current Behavior

The constructor and all six enums are built, with forty-two tests covering the
properties that are invisible when they break. What remains is conversion:
`004-liveness.lua` and the three existing declarations still carry hand strings,
so both spellings of every hand are still in the tree.

Building this surfaced something the design did not anticipate. The project has
loaded siblings with plain `dofile` since the beginning, which re-executes the
file every time. For a module returning functions that is harmless; for an enum
it mints a fresh set of members on every load, so a step built by one caller
fails to index a dispatch table built by another, and the failure reads as *no
mechanism for this hand* while the hand is plainly right there. Identity-carrying
modules therefore need single-instance loading, which is `024-load.lua` —
memoised by normalised path, kept single itself through `package.loaded`.

The first thing the enums caught was in the vocabulary sketch, on the first run
after wiring: it declared a hand named `res` where the enum says `resident`.
That is exactly the class of miss the whole file exists to prevent, and it had
already happened before anything enforced it. The abbreviation now lives on the
enum beside the full name, so a fixed-width column prints `res` without anyone
inventing it.

## Intended Behavior

An enum is a small, closed, ordered set of named members, and **a member is a
unique table rather than a string**. Two consequences follow, and they are the
whole point:

**Identity is the comparison.** `value == Hands.cold` is a pointer comparison.
No other value in the process can equal it — not the string `"cold"`, not a
member of a different enum that happens to share a name. Being right is
structural rather than a matter of having typed the same letters twice.

**A member knows which enum it came from.** Each carries a back-reference, so
`Hands.holds(value)` answers "is this one of mine" without inspecting names.
That is the question a dispatcher actually asks, and today it cannot be asked
at all.

### The shape

```
Hands.cold                  a member
Hands.cold.name             "cold"
Hands.cold.index            1
Hands.cold.enum             Hands
tostring(Hands.cold)        "cold"

Hands.of("cold")            the member, or nil plus a refusal naming near matches
Hands.holds(value)          true when value is one of this enum's members
Hands.members               ordered array, for iteration and for printing
```

`of` is the boundary crossing. Text arriving from a terminal, from JSON, or
from a database column is a string; it becomes a member exactly once, at the
edge, and everything inward of that edge compares by identity. A string that
names nothing is refused there, naming what was expected, rather than travelling
inward to fail as a lookup that quietly found nothing.

### Routing

The routing this exists for is a dispatch table keyed on members:

```
MECHANISMS[step.hand].perform(handle, step)
```

One index, not a walk down a chain of comparisons, and the key cannot be a
near-miss spelling because a near-miss spelling is not a member and would have
been refused at the edge where it entered.

### The enums to define

| Enum | Members | Replaces |
|------|---------|----------|
| `Hands` | cold, live, resident, none | string literals in declarations and liveness |
| `Kinds` | read, change, final | the `reversible` boolean, which had two states for three |
| `Refusals` | unknown, argument, unavailable, refused | a table in a document that no code reads |
| `Slots` | the nineteen equipment slots | raw slot numbers at the point of use |
| `Stats` | strength, agility, stamina, intellect, spirit, and the rest | raw stat indices |
| `Classes` | the nine playable classes, with their colours | class ids and hex colours in the chat window |

`Kinds` deserves note: it exists because `reversible = true/false` cannot say
that `character.retire` writes a receipt which records what was destroyed and
cannot put it back. Two states were being asked to hold three, and the third is
the dangerous one.

## Suggested Implementation Steps

1. Write the constructor. It takes an ordered list of names plus optional
   per-member data, and returns a frozen table carrying the members, `of`,
   `holds`, and `members`.
2. Make members immutable. A member whose `name` can be reassigned is a member
   that can be made to lie, and the whole guarantee rests on members being
   exactly what they were built as.
3. Make an unknown name a refusal that lists the members. The refusal text is
   the only thing telling a caller — a person or a model — what would have
   worked.
4. Define the six enums as separate files, so a reader looking for the slot
   list finds a file named for slots rather than a section of a large one.
5. Convert `004-liveness.lua` and the three existing declarations to members.
   Both spellings of every hand disappear from the codebase in the same edit.
6. Test the property that matters: a foreign string equal in name is not equal
   in identity, and `holds` tells the two apart.

## Open Questions

- **Do members survive JSON?** A receipt written today stores `hand = "cold"`.
  Encoding a member has to produce that string and decoding has to produce the
  member, or every receipt already on disk stops being readable. The encoder
  needs to know; the decoder needs to be told which enum it is reading into.
- **Should `of` accept a member?** Passing an already-converted member to `of`
  is either a caller being careless or a caller being defensive, and letting it
  through quietly makes the boundary fuzzy. Refusing it makes the boundary
  exact and makes some correct code fail.
- **Where do the slot and stat numbers come from?** They are the game client's,
  not ours, and getting one wrong writes to the wrong column of
  `character_stats`. They should be sourced from the core's own headers rather
  than typed from memory, and nothing currently does that.

## Related

- `docs/datapath-operation-dispatch.md` — the failure vocabulary this makes real
- `docs/vocabulary.txt` — the hands and kinds columns are these enums, printed
