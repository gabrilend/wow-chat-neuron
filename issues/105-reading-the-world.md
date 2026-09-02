# 105 — Reading the World

## Status
- Phase: 1 (Reach)
- Blocked by: 102 (cold hand)

## Current Behavior

SQL can be run, but nothing knows what a character is. Every operation would
have to write its own query against the `characters` table and its own
interpretation of the columns.

## Intended Behavior

A read layer that turns rows into the small number of record types the rest of
the project actually talks about. Operations ask for "the characters in this
roster" and get records; they never write `SELECT` themselves.

This is the boundary between generation and viewing that the project keeps
everywhere: the read layer produces data, operations consume it, and neither
knows how the other works.

### The character record

Read from `acore_characters_<profile>.characters`. Fields, down to primitives:

| Field | Type | Column | Meaning |
|-------|------|--------|---------|
| `guid` | integer | `guid` | Permanent identity. The thing to key on. |
| `name` | string | `name` | Display name. Not unique across realms; unique here. |
| `account` | integer | `account` | Which account owns it |
| `race` | integer | `race` | 1 Human, 2 Orc, 3 Dwarf, 4 Night Elf, 5 Undead, 6 Tauren, 7 Gnome, 8 Troll, 10 Blood Elf, 11 Draenei |
| `class` | integer | `class` | 1 Warrior, 2 Paladin, 3 Hunter, 4 Rogue, 5 Priest, 6 Death Knight, 7 Shaman, 8 Mage, 9 Warlock, 11 Druid |
| `gender` | integer | `gender` | 0 male, 1 female |
| `level` | integer | `level` | Current level |
| `online` | boolean | `online` | **The field the guard in issue 104 turns on** |
| `map` | integer | `map` | 0 Eastern Kingdoms, 1 Kalimdor, 530 Outland, 571 Northrend |
| `zone` | integer | `zone` | Area id |
| `x`, `y`, `z` | number | `position_x/y/z` | Where the row says they are |
| `o` | number | `orientation` | Facing, radians |

`online` is the field this whole layer exists to make unmissable. It is read on
every character fetch, whether or not the caller asked, because forgetting to
read it is the mistake issue 104 is written to prevent.

### Position is a claim, not a fact

For an **offline** character the row is authoritative — nothing else holds
their position.

For an **online** character the row is a stale snapshot from the last save.
The live position lives in the worldserver's memory. A character record for an
online character therefore carries its coordinates *and* the knowledge that
they are approximate, and any operation reasoning about where someone actually
is must use the live hand.

### Other records this layer provides

- **Group** — from `groups` and `group_member`. Which characters are partied
  with which, regardless of login state. Needed by phase 4.
- **Inventory** — from `character_inventory` joined to `item_instance` and
  `item_template`. What a character owns and where it sits. Needed by phase 3.
- **Deployment summary** — counts for the status board: characters total,
  characters online, groups, generated bots.

### The counting rule

Documentation does not carry numbers. "There are 214 characters" goes stale the
moment someone makes another one. The summary function *is* the number, and
documents point at it rather than transcribing it.

## Suggested Implementation Steps

1. Write the character-record constructor: one query, one row-to-record mapping,
   with `online` converted to a real boolean rather than left as `0`/`1`.
2. Write the lookups: by GUID, by name, by list of names, by list of GUIDs, and
   all-online. The list forms take one query with a placeholder list, not N
   queries — this is the difference between a roster of forty being one round
   trip and forty.
3. Write the race, class, and gender lookup tables as dispatch tables keyed by
   the integer, so a record can be printed in words without a chain of
   comparisons.
4. Write the group reader.
5. Write the inventory reader.
6. Write the deployment summary.
7. Write the `.info.md` describing each record's fields down to primitives.

## Open Questions

- **Should a character record cache?** Within one plan, the same character may
  be read several times. Caching within a single dispatch is safe; caching
  across one is exactly how a stale `online` flag gets used. Scope any cache to
  the dispatch, or do not write one.
- **What about characters on other realms?** The schema supports several; the
  deployment runs one. Everything here assumes one realm and will need a realm
  filter if that changes.

## Related

- `docs/architecture.md` — Liveness Is a First-Class Fact
- Issue 104 — the guard that consumes `online`
- Real table names confirmed against the deployment's own database directory
