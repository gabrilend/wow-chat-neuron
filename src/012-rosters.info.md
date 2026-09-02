# 012-rosters.lua

A roster is a named set of characters, resolved at the moment it is used. This is
the lookup table the project was asked for, and it belongs to the project rather
than to any one operation.

## Functions

### `Rosters.resolve(handle, specification, options) -> resolution | nil, why`

Four forms, told apart by shape:

| Specification | Read as |
|---------------|---------|
| `Grast` | One character, if that name exists |
| `Grast,Wenna` | A name list (the comma is the signal) |
| `bots hunters 18-20` | A query |

`options`: `limit` (default 200), `include_orphans`.

The resolution carries `characters`, `missing`, `truncated`, `ceiling`,
`describes`.

### `Rosters.describe(resolution) -> string`
Renders the resolution **including what was not included** — missing names,
truncation, orphan exclusion. A roster that quietly resolved to fewer characters
than asked for is how an operation reports success having done most of a job.

## The query vocabulary

Deliberately small and boring. It is a filter, not a language.

| Word | Means |
|------|-------|
| `20`, `level20` | Exactly that level |
| `18-20` | That level range |
| `hunter`, `hunters`, `mage`… | That class |
| `draenei`, `troll`… | That race |
| `bot` / `bots` | Bot accounts |
| `person` / `people` | Real, non-bot accounts |
| `orphan` / `orphans` | No account row at all |
| `online` / `offline` | Login state |

**An unrecognised word is an error**, not ignored. A query with a typo that
silently matches everything is how a roster resolves to twenty-five thousand
characters and somebody moves all of them.

## Three guards, all reported

- **Missing names** are returned, never dropped.
- **Orphans excluded** by default (900 exist on the live deployment).
- **A ceiling** applied and reported, so truncation is visible.

## Resolution happens at use time

Never at definition time. A roster meaning "bots between 18 and 20" means
different characters next week, and that is the point — a stored list silently
goes stale and moves the wrong forty.
