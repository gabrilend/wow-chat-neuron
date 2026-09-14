# 026-enum.lua

A closed, ordered set of named members, where **a member is a unique table
rather than a string**.

Covers this file and the six enums beside it, whose interface is entirely this
one's.

## Functions

### `Enum.define(name, definitions) -> enum`
`definitions` is an ordered array. Each entry's first positional element is the
member's name; every other key becomes a field on the member, so per-member data
— a class's colour, a slot's number — lives where the member is declared rather
than in a parallel table that can fall out of step.

### `Enum.name_of(value) -> string`
The name, for anything on its way out to text: a receipt, a JSON body, a SQL
bind. **A member is an empty proxy table, so handing one to the JSON encoder
produces `{}` rather than `"cold"`, silently.** Everything crossing back out
goes through here.

## What an enum gives you

| | |
|---|---|
| `Hands.cold` | the member |
| `Hands.cold.name` / `.index` / `.enum` | its name, position, and which enum it came from |
| `Hands.of(text)` | member, or nil plus a refusal naming near matches |
| `Hands.holds(value)` | is this one of mine |
| `Hands.members` | ordered array |
| `Hands.names()` | ordered array of strings |
| `tostring(Hands.cold)` | `"cold"` |
| `Hands("cold")` | same as `.of` |

## The two properties everything rests on

**Identity is the comparison.** `value == Hands.cold` is a pointer comparison.
Nothing else in the process can satisfy it — not the string `"cold"`, not a
member of another enum with the same name, not a hand-built table carrying the
same fields.

**A member knows its enum.** `holds` reads a back-reference, so the question a
dispatcher actually asks — *is this one of mine* — can be asked at all. A string
cannot answer it.

Members are immutable through a proxy: the table handed out is empty, reads go
through `__index` into hidden storage, writes hit a `__newindex` that refuses,
and `__metatable` is locked so none of that can be undone.

## `of` refuses a member

Passing an already-converted member back into `of` is refused rather than
returned. It means the caller has lost track of whether it holds text or a
member, and letting it through makes the boundary fuzzy exactly where its whole
value is that it is sharp.

## The six

| File | Enum | Members |
|------|------|---------|
| `027-hands.lua` | `Hands` | cold, live, resident, none — each with `carries` |
| `028-kinds.lua` | `Kinds` | read, change, final — each with `glyph`, `declares`, `captures_prior` |
| `029-refusals.lua` | `Refusals` | unknown, argument, unavailable, refused |
| `030-slots.lua` | `Slots` | the nineteen equipment slots, with `.slot` |
| `031-stats.lua` | `Stats` | the five primary attributes, with `.stat` |
| `032-classes.lua` | `Classes` | the nine classes, with `.id`, `.colour` |

**Read `.slot`, `.stat` and `.id`, never `.index`.** The constructor's `index`
is 1-based position; the game's numbering is its own and disagrees. Slots run
0–18 so index is off by one throughout; classes have a real gap where id 10
would be.

## Unverified numbers

`030-slots.lua` and `031-stats.lua` carry values written from knowledge of the
3.3.5a core rather than read out of it, because no source tree is cloned in this
worktree. Both files carry a block naming the header to grep once one is. A
wrong slot number does not error — it puts boots on a head; a wrong stat index
adds strength to the intellect column.
