# Everland Ghostsong - Claude Instructions

*Technical name: wow-chat-2 (epitome-graph)*

## Session Initialization

**On new session or context compaction:** Read `docs/concept-catalog.md` to restore project knowledge. The catalog contains 800 concepts covering all game systems, algorithms, configuration, and design philosophy. This is essential context for working on this project.

## Project Overview

Everland Ghostsong is a WoW 3.3.5a private server with custom roguelike survival mechanics. The world is empty by default - monsters spawn around players (ambush system), treasure spawns, and traveler NPCs wander the world. Players use playerbots as AI companions.

**Max level is per-profile** (set by `config/patches/C006*`): vanilla 40, beta 20, release/alpha 80. Talent points every 1/3 level; abilities earned through quests and training.

### Profiles

The project builds several profiles from shared source, each with its own
installed tree (`installed-files-<profile>/`), database set, and config-patch
tuning. The active profile lives in `.profile`; scripts read it to select the
matching source tree, install dir, and databases.

- **release** / **alpha** — level cap 80 (retail-like baseline)
- **beta** — level cap 20 (the original wow-chat roguelike design)
- **vanilla** — level cap 40 (classic-era shape; currently the active profile)

release/beta/vanilla share `source-beta`; alpha uses `source-alpha`. Per-profile
differences are applied at install time by `config/patches/C*.sh`, gated on the
profile name.

## Documentation Locations

### Local Documentation (docs/)

- **docs/playerbots/** - Playerbot module documentation

- **docs/ale/** - AzerothCore Lua Engine (ALE) API documentation

- **docs/wiki/** - AzerothCore wiki (server administration)
  - Database structure, SQL queries, server configuration

- **docs/architecture.md** - System architecture and data flow
- **docs/configuration.md** - Configuration options reference
- **docs/scripting.md** - Lua scripting quick reference

### Concept Catalogs (docs/)

- **docs/concept-catalog.md** - 800 concepts (001-800)
  - Foundation, Behavior, Config, Data, Math, Visual, Integration, Workflow
  - Appendix with cross-references by system, phase, and file

- **docs/concept-issue-map.md** - Issue-to-concept cross-reference
  - Maps each issue file to relevant concepts
  - Reverse lookup: concept ranges → issues
  - Statistics on concept coverage
  - **Update when:** new issues created, issues completed, concepts added/modified

### Key Lua Files (src/lua-beta/)

The per-profile Lua dirs (added 2026-06-02): `src/lua-beta/` is the
wow-chat design corpus (formerly `src/lua/`); `src/lua-vanilla/`
holds vanilla-only scripts (currently just the starter-equipment
hook from 148k); `src/lua-alpha/` is a placeholder for alpha-era
mod-eluna scripts. E001 symlinks the profile-matching dir into
`installed-files-${PROFILE}/bin/lua_scripts/custom/`.

- `ambush.lua` - Monster spawn system (120-160 yards from player)
- `travel.lua` - Traveler NPC wandering behavior
- `movement.lua` - Movement utility functions (angles, distances, positions)

## Build and Run

```bash
# Build/update server
./scripts/azerothcore update

# Start MySQL (required first)
./scripts/start-mysql

# Run servers
./scripts/azerothcore authserver
./scripts/azerothcore worldserver
```

## Database

- MySQL runs on port 3307 (project-local installation)
- Credentials: ritz / menardi
- Databases: acore_auth, acore_characters, acore_world, acore_playerbots

## Modules Installed

- **mod-ale** - Lua scripting engine (hot-reload capable)
- **mod-playerbots** - AI companion bots
- **mod-aoe-loot** - Area loot for convenience
- **mod-grownup** - Scale player models by level
- **AIO** - Server-to-client addon framework

## Directory Structure

### issues/ vs tissues/

- **issues/** - Tasks for computer constructonomy (code, automation, systems)
- **tissues/** - Tasks for human expert analysis (design decisions, balance, narrative)

The worker who attends to the goings on. Some things need machines, some need human experts.

## Coding Style (Lua)

This is singing.

### Vertical Alignment
Connect things at the same X value in the page to signify meaning.
Account for all characters preceding - alignment creates relationship.

```lua
-- values of connecting relevance align vertically
local SPAWN_MIN_DIST   = 120
local SPAWN_MAX_DIST   = 160
local SPAWN_MIN_HEIGHT = -15
local SPAWN_MAX_HEIGHT =  15

local ORBIT_RADIUS     =  10
local ORBIT_SPEED      =   5
local ORBIT_DIRECTION  =   1
```

### Dense Math, Few Functions
Lots of math, fewer functions. Long, dense configurations with few validation checks.
Get it right the first time. Ensure the piping is sound.

```lua
-- prefer inline calculation over helper calls
local x = originX + math.cos(theta) * radius
local y = originY + math.sin(theta) * radius
local z = map:GetHeight(x, y)

-- not
local x, y = Movement.getPositionAtAngle(originX, originY, theta, radius)
```

### Configuration in Structure, Not Data
Maintain configuration in code structure, not runtime data.
Git greps are cheap.

```lua
-- structure holds the configuration
local SpawnConfig = {
    ambush = { min = 120, max = 160, timer = 40  },
    travel = { min =  50, max = 100, timer = 130 },
    chest  = { min =  30, max =  60, timer = 100 },
}
```

### Comments Abound
- Self-documentation is for human viewers
- Comments are for machines to store notes
- Comments provide extended context when humans ask

```lua
-- {{{ calculateOrbitPosition
-- Monster orbits the player at radius, moving at speed
-- Direction: 1 = clockwise, -1 = counter-clockwise
-- Returns new x, y position after dt seconds
function calculateOrbitPosition(px, py, radius, speed, dt, angle, dir)
    local angular = speed / radius              -- radians per second
    local newAngle = angle + (angular * dt * dir)
    local x = px + math.cos(newAngle) * radius
    local y = py + math.sin(newAngle) * radius
    return x, y, newAngle
end -- }}}
```

### Use Vertical Space
Breathe. Group related operations. Separate concerns with whitespace.

```lua
function spawnAmbush(player)
    -- get player state
    local px, py, pz = player:GetPosition()
    local level      = player:GetLevel()
    local mapId      = player:GetMapId()

    -- calculate spawn position
    local theta  = math.random() * 6.28
    local radius = math.random(SPAWN_MIN_DIST, SPAWN_MAX_DIST)
    local x      = px + math.cos(theta) * radius
    local y      = py + math.sin(theta) * radius

    -- validate height
    local map = GetMapById(mapId)
    local z   = map:GetHeight(x, y)

    if math.abs(z - pz) > SPAWN_MAX_HEIGHT then
        return nil  -- too high/low, abort
    end

    -- spawn creature
    local entry    = selectCreatureForLevel(level)
    local creature = PerformIngameSpawn(1, entry, mapId, 0, x, y, z, 0)

    return creature
end
```

## Ambush Spawn System

### Spawn Interval (Random Walk)
The ambush spawn interval uses a random walk algorithm:
- Base interval: 40 seconds
- Each spawn, interval changes by +/- 2, 3, or 4 seconds from *previous* value
- Floor: 10 seconds (only goes up when reached)
- Soft cap: 100 seconds (33% up, 67% down)
- Hard cap: 200 seconds (20% up, 80% down)

### Grace Period
- 30 second fixed grace period on login
- Only triggers if offline for 10+ minutes
- Quick relogs (< 10 minutes) resume random walk immediately

### Configuration (src/lua-beta/ambush.lua)
```lua
AMBUSH_BASE_INTERVAL   =  40000  -- ms starting interval
AMBUSH_INTERVAL_MIN    =  10000  -- ms floor
AMBUSH_INTERVAL_SOFT   = 100000  -- ms soft cap
AMBUSH_INTERVAL_HARD   = 200000  -- ms hard cap
AMBUSH_JITTER_MIN      =   2000  -- ms minimum jitter
AMBUSH_JITTER_MAX      =   4000  -- ms maximum jitter
AMBUSH_GRACE_PERIOD    =  30000  -- ms grace period on login
AMBUSH_OFFLINE_RESET   =    600  -- seconds offline to trigger grace
```

## Visual Powerline Mapping

### pngs/ Directory Structure

Parallel to `src/`, the `pngs/` directory holds annotated screenshots:

```
src/lua-beta/behaviors/find-monsters.lua    →    pngs/lua/behaviors/find-monsters.png
src/lua-beta/behaviors/avoid-monsters.lua   →    pngs/lua/behaviors/avoid-monsters.png
src/lua-beta/movement.lua              →    pngs/lua/movement.png
```

### Powerline Generation (Automatic)

The powerline tool parses source files and procedurally generates maps:

1. Tool parses all files in `src/`
2. Indexes identifiers: functions, globals, constants, datastructures
3. Detects cross-file and cross-statement references
4. Renders source to .png with syntax highlighting
5. Draws powerlines between detected references automatically
6. Outputs to parallel `pngs/` directory
7. User enhances generated maps as needed to highlight specific meanings

### Powerline Principles

- **Vertical alignment first** - if you can align it in source, do that
- **Powerlines as stop-gap** - for cross-file connections that can't be vertical
- **Semantic over syntactic** - connect by meaning, not proximity
- **Editor-rendered** - powerlines exist in viewing layer, not source code

### Refactoring Actions

- **Skooch** - adjust alignment so one element clears another visually
- **Wave** - align config points across files to create visual flow

See `issues/117-visual-powerline-mapping-tool.md` for full specification.

## Commit Conventions

- **Bundle the LLM transcripts into every commit.** Session transcripts in
  `llm-transcripts/` ride along with whatever else is committed — even when
  they belong to a different ongoing discussion. This is automated by a local
  `.git/hooks/pre-commit` that runs `git add -A llm-transcripts/`. That hook
  lives under `.git/` and is not itself version-controlled, so **after a fresh
  clone, re-create it** (or the transcripts stop getting bundled). User
  directive, 2026-07-16.

## Patch System

We don't hard-fork the AzerothCore core, modules, or ALE. The cloned source
trees (`source-beta/`, `source-alpha/`) are regenerable build artifacts; our
customizations live as reversible apply/unapply scripts that re-derive on every
build and revert afterward, so the tree always round-trips clean to upstream
HEAD:

- `patches/B*.sh` — C++/source patches (compile fixes, module behavior),
  applied before compile and reverted after.
- `config/patches/C*.sh` — config-value patches applied to the generated
  `.conf` files at install time, gated per-profile via `CONFIG_PROFILES`.
- `patches/E-patches.sh` — install-time setup (config init, SQL, symlinks).
- `patches/patches.sh` — the per-profile patch lists and the runner.

Built with the **`upstream-patch-system` skill** at
`/home/ritz/programming/ai-stuff/skills/`. Read it before adding, removing, or
retargeting a patch: its apply/unapply, idempotency, and marker conventions are
what keep the round-trip to upstream clean.

## Documentation as Code

### Patch Documentation (docs/patches/)

When modifications require changes to C++ source (ALE, AzerothCore core, modules),
write patch documentation instead of directly modifying files. This approach:

1. **Describes exactly what to change, where**
   - File paths relative to source root
   - Line numbers or context for insertion points
   - Complete code snippets ready to paste
   - Before/after when modifying existing code

2. **Readable by LLMs or humans**
   - An AI agent can read the patch doc and apply it to any compatible fork
   - A human can follow the same instructions manually
   - Non-deterministic interpretation produces same outcome protocols
   - The description IS the implementation specification

3. **Portable across forks**
   - Works with any ALE-compatible Lua engine
   - Works with any AzerothCore fork
   - Describes behavior, not specific commit hashes
   - Finds insertion points by context, not line number alone

### Patch Doc Structure

```markdown
# [Feature Name] Patch

## Overview
Brief description of what this patch adds.

## Files to Modify

### 1. `path/to/file.cpp`
[Context and code changes]

### 2. `path/to/other/file.h`
[Context and code changes]

## Usage
How to use the feature after applying.

## Build Instructions
Commands to rebuild after patching.
```

### Example: `docs/patches/ale-sell-item-hook.md`

Adds `PLAYER_EVENT_ON_SELL_ITEM` to ALE. Describes changes to:
- `Hooks.h` - enum addition
- `LuaEngine.h` - method declaration
- `PlayerHooks.cpp` - implementation
- `ItemHandler.cpp` - hook call site

Any LLM reading this file can apply the patch. Any human can too.
The patch doc is the source of truth for the modification.

### Issue Files vs Patch Docs

- **Issue files** (`issues/`) - Describe BEHAVIOR
  - What the system should do
  - Why it should do it
  - Implementation steps (abstract)
  - Can be implemented in any language, any architecture

- **Patch docs** (`docs/patches/`) - Describe CHANGES
  - Exact code modifications
  - Specific to one codebase/language
  - Ready to apply mechanically
  - Implementation of an issue's requirements

Issue files are portable across reimplementations.
Patch docs are portable across forks of the same codebase.

### Why This Matters

The game server runs on open-source C++. We can modify it.
But we don't want to maintain a hard fork with merge conflicts.

Patch documentation:
- Preserves the modification as knowledge
- Allows reapplication after upstream updates
- Enables review before application
- Creates a paper trail of customizations
- Can be shared without sharing compiled binaries

- at all times, when possible, try to utilize the design patterns presented in the original wow-chat-1 reference source.
- girl just search the database next time, don't do so many web searches.
- a good error message has each value checked and verified at message-creation time, each idempotent. Possible causes can be filled in periodically (focusing on the most common or rarest) as derived from related issue files. It should offer questions about the potential results of its "to debug:" suggestions, explaining each succinctly and clearly. The error reports both what didn't complete AND what did, so the reader knows where in the pipeline things stopped.
- let me run the compilation scripts. I want to see the output.