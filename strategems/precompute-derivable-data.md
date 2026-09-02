# Strategem: Precompute Derivable Data

A strategem is a data flow pattern that recurs across multiple areas
of the project and has been proven useful enough to standardize. This
one says:

> If a value is fully derivable from static rules — a formula, a fixed
> set of IDs, a configuration constant — compute it once and store it
> in a table that runtime code reads with a single indexed lookup.
> Never compute it on the hot path; never query a database for it
> mid-game.

The pattern crosses Lua and C++ alike. The shape is always the same:
declarative-data-up-front, opaque-lookups-during-play.

## The two flavors

### Source-baked

The data lives **as literal source code**. A Lua table or a C++ array
constant, hand-written or generated, sitting in the file that uses
it. The compiler / interpreter loads it as part of loading the file.

Reach for source-baked when the data is **design-decided**: a list of
treasure IDs you've curated, a banned-creatures list, a class-spell
mapping, a level cap, a curve constant. The data is part of the
design intent, and it should be visible to anyone reading the file.

Examples in the project:

- `libs/wow-chat-1/treasure.lua` — `local chests = { { id=2843, minLevel=1, maxLevel=5 }, ... }`
  is a literal array of records. Tuning a chest means editing the
  source.
- `src/lua/ambush.lua` constants — `AMBUSH_BASE_INTERVAL = 40000`,
  the `type IN (2, 3, 4, 5, 6, 9, 10)` SQL whitelist (the comment
  above it spells out what each number means) — same idea, smaller
  scope.

### Runtime-seeded

The data lives in **a table that's populated once at startup** from
some other source — usually a SQL query or a derived calculation.
After the seed step, runtime code never re-queries; it only reads
from the in-memory table.

Reach for runtime-seeded when the data is **query-derived**: it lives
authoritatively in the DB (or in another module's state), is too
large or volatile to hand-maintain in source, but doesn't change
during a server session.

Examples in the project:

- `src/lua/ambush.lua.disabled::Ambush.initCreatureCache()` — populated
  `CreatureCache[level][rank] = { ids }` at `ELUNA_EVENT_ON_LUA_STATE_OPEN`
  by issuing one SQL query per `(level, rank)` combination. Runtime
  spawn code then looked up from the in-memory table instead of
  re-querying.
- (Future) `Spell.IDByClassByLevel[class][level]` could be seeded
  from `class-spells-level-1-20.md` at script load. Currently lives
  in scattered places.
- (Future) C++ `Creature::s_aggroRadiusTable[absLevelDiff]` will be
  populated at static init by the B024 patch (see "Implementation
  templates" below).

## When to use which

Decision table:

| Data character | Flavor | Rationale |
|----------------|--------|-----------|
| Design constants the author types directly | Source-baked | Greppable, comment-able, version-controlled with the consuming code |
| Hand-curated lists of game IDs | Source-baked | Editing the list IS the design action; SQL would be indirection |
| A formula's output range | Source-baked (precomputed table) | The formula IS the design; the table is a cache of it |
| Large derivative of a DB table | Runtime-seeded | Source would be unmaintainable; one query at startup beats N queries during play |
| Anything that changes during a session | **Neither** — query live | Caches that go stale are bugs waiting to happen |

## Why this is worth doing

The benefits compound:

- **Eliminates async-query plumbing** for static data. Saves the entire
  SQL → callback → ALE bridge round-trip every time the cache is
  consulted. (And sidesteps the FormatQuery bug from issue 141
  for the duration of any future ALE bugs in that pathway.)
- **Makes data visible** in source. A reader who greps for an NPC ID
  finds where it's used; a reader who greps for a level constant
  finds the curve it shapes.
- **Performance is O(1)** after the seed step. Formula loops shrink to
  one array index.
- **Tunability becomes per-cell**, not per-formula. If you ever decide
  level-1 vs level-80 should have a custom aggro value not predicted
  by the curve, you just edit that one cell. The formula is the
  default; the table holds the design.
- **Forces clarity at design time**. "What's the level cap?" gets one
  answer (the constant), not "depends on which file you're in."

## Implementation templates

### Lua source-baked

```lua
-- module-top scope, before any function definitions
local CreatureTypeMeaning = {
    [2]  = "Dragonkin",
    [3]  = "Demon",
    [4]  = "Elemental",
    [5]  = "Giant",
    [6]  = "Undead",
    [9]  = "Mechanical",
    [10] = "Aberration",
}

-- runtime code
local label = CreatureTypeMeaning[creatureType] or "Unknown"
```

### Lua runtime-seeded (mirrors `ambush.lua.disabled`)

```lua
local Cache = {}  -- module-local, never reassigned after seed

local function seedCache()
    Cache = {}
    for level = 1, MAX_LEVEL do
        Cache[level] = {}
        for _, rank in ipairs({0, 2, 4}) do
            Cache[level][rank] = {}
            local q = WorldDBQuery("SELECT ...")
            if q then repeat
                table.insert(Cache[level][rank], q:GetUInt32(0))
            until not q:NextRow() end
        end
    end
end

RegisterServerEvent(ELUNA_EVENT_ON_LUA_STATE_OPEN, function()
    seedCache()
end)
```

Note: runtime-seeded caches use SYNC `WorldDBQuery` at startup, not
`WorldDBQueryAsync`. Startup is single-threaded; sync is appropriate.
The B023-fixed FormatQuery bug doesn't bite here because we don't
pass format args to the seed queries.

### C++ source-baked precomputed table

This example is shown with comments for explanation; if you copy it
into a B-patch that modifies upstream C++, strip the explanatory
comments — they belong in the patch's `.sh` header or issue file,
not in the inserted code. (See `feedback_no_explanatory_comments_in_patched_source.md`
in memory, or the B024 patch for the comment-free form.)

```cpp
namespace {
    constexpr int AGGRO_TABLE_SIZE = 80;
    std::array<float, AGGRO_TABLE_SIZE> const s_aggroRadiusByAbsDiff = []() {
        std::array<float, AGGRO_TABLE_SIZE> t{};
        for (int i = 0; i < AGGRO_TABLE_SIZE; ++i) {
            int decaySteps = (i > 3) ? i - 3 : 0;
            float r = 20.0f;
            for (int j = 0; j < decaySteps; ++j) r *= 0.9f;
            t[i] = r;
        }
        return t;
    }();
}

// In the hot-path function:
int32 absDiff = (levelDiff < 0) ? -levelDiff : levelDiff;
if (absDiff >= AGGRO_TABLE_SIZE) absDiff = AGGRO_TABLE_SIZE - 1;
float retDistance = s_aggroRadiusByAbsDiff[absDiff];
```

The lambda-initialized `std::array` is the C++ equivalent of "seed at
load time, read forever after." Used by B024 (issue 142). Alternative
placement: function-local `static const` so the table only initializes
on first call (C++11 magic-statics handles thread-safe init). B024
uses the function-local form to scope the table tightly to its one
consumer.

## Naming conventions

- **Lua source-baked**: `local PurposeName = { ... }` at module top.
  PascalCase, no `Cache` suffix unless it's actually seeded from
  somewhere.
- **Lua runtime-seeded**: `local PurposeNameCache = {}` at module top,
  reassigned only inside the seed function. PascalCase + `Cache`
  suffix signals "this was filled from elsewhere."
- **C++ source-baked**: `s_purpose_name_table` or `s_purposeNameTable`
  at anonymous-namespace scope, `constexpr` if the table contents can
  be computed at compile time, otherwise `const` initialized via
  lambda. The `s_` prefix marks file-scope static.

## Invalidation policy

**Default: never invalidate.** A cache that can go stale is worse than
no cache. If you find yourself needing to invalidate, the data
probably belongs in a live query, not a cache.

The narrow exception: runtime-seeded caches MAY be re-seeded on
explicit GM command (e.g. `.reload script ambush`) for development.
Production code should not have a "refresh the cache" path that fires
during normal play.

## When NOT to use this strategem

- Data that depends on **per-instance state** (a specific creature's
  current HP, a specific player's loot history). Always live.
- Data whose **size approaches main-memory cost**. 25 KB of aggro
  table is free; 25 MB of every-possible-spell-effect-precomputed
  is not.
- Data where the **lookup key changes during a session in
  unbounded ways** (coordinates, GUIDs of dynamically-spawned
  objects).

## Related

- `docs/patches/contributing-upstream.md` — when a precomputed table
  fixes an upstream perf bug, the upstream PR follows the same
  workflow as any other B-patch port.
- `issues/142-symmetric-aggro-radius.md` — first C++ application of
  this strategem (B024).
- (Pending) `issues/2XX-ambush-creature-id-cache.md` — port the
  `ambush.lua.disabled::initCreatureCache` runtime-seed back into
  active ambush.lua as the first big Lua application.
