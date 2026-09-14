# 075-reading-order.lua

The index of the project, read back out of the project. Produces the table in
`docs/reading-order.md` — every source file, in ascending index order, each
described by its own opening sentence.

Reached through `scripts/reading-order`. Nothing else in the project loads it;
the document it writes is for people.

## Why it is generated

The table used to be kept by hand and drifted three ways at once: twenty-three
entries short, listing three files that had been replaced, and out of numeric
order in a document whose only claim is that numeric order *is* the order. None
of that is visible — a stale table renders perfectly and a reader believes it.

There is now one copy of each sentence, in the file it describes.

## Where a description comes from

Every source file opens the same way, and the reader is anchored to that shape
rather than searching for prose:

| Line | Holds |
|------|-------|
| 1 | a rule of dashes |
| 2 | `-- <the file's own name>` |
| 3 | `--` |
| 4+ | the summary, which may wrap, ending at a blank `--` or the closing rule |

The summary is then cut back to its first sentence, plus the second one when the
first is under 48 characters and the second would not take it past 180. A
filename is about thirty characters wide, so a shorter description has barely
out-told the name sitting beside it.

**To change a row in the table, change the sentence at the top of the file it
describes, then run `scripts/reading-order`.**

## Functions

### `ReadingOrder.summary_of(path)`

| | |
|---|---|
| `path` | string — absolute path to a `.lua` source file |
| returns | string — the file's own summary sentence |
| on failure | `nil, string` — the file could not be opened, or has nothing on line 4 |

### `ReadingOrder.rows(root)`

Walks `root/src` and returns every indexed thing in reading order.

| | |
|---|---|
| `root` | string — absolute path to the project root |
| returns | array of row tables, sorted ascending by index |
| on failure | `nil, string` — a file with no index on its name, or a group directory with no description |

Each row is a table of three strings:

| Field | Type | Holds |
|-------|------|-------|
| `index` | string | the digits off the front of the name, e.g. `"026"` — a string, not a number, because the leading zeros are part of how it is written everywhere else |
| `path` | string | project-relative, e.g. `"src/025-enums/026-enum.lua"`; a group directory ends in `/` |
| `describes` | string | the sentence, ready to drop in a table cell |

A group directory appears as its own row immediately above its contents. It gets
there by holding the lower index, not by anything sorting it specially.

### `ReadingOrder.table_for(rows)`

| | |
|---|---|
| `rows` | array from `ReadingOrder.rows` |
| returns | string — the markdown table, both markers included |

### `ReadingOrder.rewrite(document, replacement)`

Swaps everything between the two markers.

| | |
|---|---|
| `document` | string — the whole of `docs/reading-order.md` |
| `replacement` | string — from `ReadingOrder.table_for` |
| returns | string — the document with the table replaced |
| on failure | `nil, string` — a marker is missing, or they are the wrong way round |

It refuses rather than repairs. A document that has lost its markers was edited
by somebody who did not know the table was generated, and guessing where the
table went would overwrite what they wrote.

## Values

| Name | Type | Is |
|------|------|-----|
| `ReadingOrder.BEGIN_MARKER` | string | `<!-- begin generated: the count so far -->` |
| `ReadingOrder.END_MARKER` | string | `<!-- end generated -->` |

## Adding a group directory

A new directory under `src/` whose name starts with an index is a group, and it
needs a sentence in the `GROUPS` table inside this file. Without one the
generator **stops with an error** rather than leaving the row out — a silently
missing group is an index that has vanished from the count.

## Related

- `scripts/reading-order` — the wrapper: rewrite, `--stdout`, or `--check`
- `tests/075-reading-order.test.lua` — including the check that the document on
  disk matches what the source says it should be
- `tests/banners.test.lua` — that every file names itself correctly on line 2,
  which is the line this reads the index from
- `src/019-vocabulary.lua` — the other generated document, same arrangement
