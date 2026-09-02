# 005-world-read.lua

Turns database rows into records. Operations ask for characters and get records;
no operation writes a SELECT.

## Functions

### `WorldRead.character_by_name(handle, name) -> character | nil, why`
### `WorldRead.characters_by_name(handle, names) -> characters, missing | nil, why`
Several characters in **one** query. Names that matched nothing come back in
`missing` rather than being silently dropped — a caller asking for forty and
receiving thirty-eight must be told which two, or it moves thirty-eight people
and reports success.

### `WorldRead.characters_by_guid(handle, guids) -> characters, missing | nil, why`
The same, keyed by GUID. Used by anything replaying a receipt: a receipt records
GUIDs, because a name in a receipt could have been given to a different
character since.

### `WorldRead.characters_online(handle) -> characters | nil, why`
Everyone the database believes is logged in. Only meaningful with the world up:
a crashed server leaves characters marked online forever.

### `WorldRead.groups(handle) -> groups | nil, why`
Every party with its members, regardless of login state. Each group has `guid`,
`leader_guid`, and `members` (each `guid`, `subgroup`).

`groups` is backticked in the query because it is a **reserved word in MySQL 8**.
Without backticks the statement is a syntax error that reads perfectly normally.

### `WorldRead.summary(handle) -> summary | nil, why`
Counts: `characters`, `bots`, `people`, `orphans`, `accounts`, `parties`,
`online`. **This function is the numbers.** Documentation must not carry
statistics; it points here instead.

`orphans` is counted separately and never folded into `people`. See below.

### `WorldRead.describe_character(character) -> string`
One character as a readable line, with race and class as words.

### Lookup tables
`WorldRead.RACES`, `.CLASSES`, `.GENDERS`, `.MAPS` — dispatch tables keyed by
the game's integer. Gaps are real: race 9 is the reserved pre-Cataclysm Goblin
slot and class 10 does not exist, so a nil lookup means "no such thing", not
"we forgot".

## The character record

| Field | Type | Notes |
|-------|------|-------|
| `guid` | number | The key for anything machine-driven; survives renames |
| `name` | string | Unique on this realm; the key for a person typing |
| `account` | number | |
| `account_name` | string or nil | **nil means orphaned** — no account row exists |
| `is_bot` | boolean | Heuristic; see below |
| `race`, `class`, `gender`, `level` | number | |
| `race_name`, `class_name`, `gender_name` | string or nil | |
| `online` | **boolean** | A real boolean, not the database's 0/1 |
| `map`, `zone` | number | |
| `x`, `y`, `z`, `o` | number | |
| `position_is_stale` | boolean | True exactly when online |

`online` is converted to a real boolean deliberately: `if row.online then` is
**true for the number 0**, so a caller that forgot to compare against 1 would
treat every offline character as online. Every guard would then misfire in the
safe direction, which is the kind of bug that hides for months.

`position_is_stale` exists because position is a claim, not a fact. For an
offline character the row is authoritative. For an online one it is a snapshot
from the last save, and the real position is in the worldserver's memory.

## Three kinds of character

Measured on the live deployment: 24,110 bots, 5 people, 900 orphans.

An **orphan** has no account row at all — its account was deleted and the
character was left behind. It belongs to nobody and cannot be logged in.

The join to the auth database is therefore **LEFT, not INNER**. An inner join
would make orphans vanish from every query in the project, which is exactly how
nine hundred rows go unnoticed. And orphans are counted on their own rather than
folded into `people`, because the first version did fold them and reported 905
people on a server with one human account.

## The bot heuristic

Nothing in the schema records that a character is a bot. mod-playerbots creates
its fleet under a configurable account-name prefix (`RNDBOT` by default), and
`is_bot` reads that prefix.

So: a human whose account starts with the prefix reads as a bot, and a fleet
created under a different prefix reads as people. The prefix is configurable in
`config/deployment.lua` for that reason, and this is documented at the point of
use rather than allowed to read as a fact.
