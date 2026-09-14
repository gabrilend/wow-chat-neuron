# 024-load.lua

Load a source file once and hand back the same value every time after.

## Functions

### `Load(path) -> value`
Runs the file if it has not run, returns what it returned. Paths are normalised
(`a/b/../c` becomes `a/c`) before being used as cache keys, so one file reached
through two spellings is one entry.

### `Load.loaded() -> array of path`
What has been loaded, sorted. For a status board, or a test proving a file was
built exactly once.

## Why it exists

The project loaded siblings with plain `dofile` from the beginning, and for
everything written before the enums that was fine — a module returning functions
and strings can be built twice with no consequence.

Enums broke it. A member is a unique table and being unique is the entire
guarantee. Load the hands enum twice and there are two `Hands.cold` tables that
are not equal to each other; a step built by one caller then fails to index a
dispatch table built by another, and the failure reads as *no mechanism for this
hand* while the hand is plainly right there.

The loader has the same problem one level up — two `dofile`s of it would build
two caches — and sidesteps it through `package.loaded`, of which the Lua runtime
keeps exactly one per process.

## Two refusals

A file that cannot be loaded, and a file that returns nothing. The second is not
pedantry: a nil cache entry and an absent one are indistinguishable, so a file
returning nil would re-run on every call, which for anything carrying identity
means new members every time — the exact failure this prevents, arriving
silently.

## Known limit

Normalisation is textual. It does not resolve symlinks, so a file reached
through a symlinked directory and through its real path is still two entries.
Fixing that needs a filesystem library this project does not depend on, and
nothing in the tree is reached both ways today.
