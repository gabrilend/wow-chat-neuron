# 011-place-book.lua

Places have names. A name resolves to a map, three coordinates, an orientation,
and a note about what it is.

Most of the book already exists: `game_tele` in the world database holds 1,989
named locations, and it is the table AzerothCore's own teleport command reads.
That produces the symmetry phase 2 rests on — the live hand's `tele name` takes
exactly these names, so one name works through both hands with no translation
layer to disagree.

## Functions

### `PlaceBook.resolve(handle, name) -> place | nil, why`
Project places first, then the game's. An exact fold-match wins; a single partial
match is accepted; **several partials return every candidate** rather than a
guess. `harbor` matches five places, and guessing then moving forty characters is
not recoverable.

### `PlaceBook.search(handle, fragment, limit) -> places | nil, why`

### `PlaceBook.remember(handle, name, character, describes) -> place | nil, why`
Capture a character's current position as a named project place. This is how
`the-ridge` comes to exist: you stand on it and name it. For an **online**
character this records the last-saved position, not where they are standing —
flagged as `from_stale_position`.

### `PlaceBook.normalise(name) -> string`
The fold: lowercase, strip everything that is not a letter or digit. Used on
**both** sides of every comparison, and it must be the same function on both —
two normalisers that drift produce a lookup that works in a test and not in life.

### `PlaceBook.ensure_table(handle)`
Creates `neuron_place` in the **characters** database. Not the world database:
that one is regenerated wholesale when a deployment re-imports upstream data, so
a project table there vanishes on the next server update.

## The place record

| Field | Type | Notes |
|-------|------|-------|
| `name` | string | As stored |
| `map` | number | |
| `map_name` | string or nil | nil means not an open-world continent |
| `is_open_world` | boolean | False means it is inside an instance |
| `x`, `y`, `z`, `o` | number | |
| `known_to_game` | boolean | **False means the live hand cannot use it** |

`known_to_game` is carried on the place so no caller has to remember that a
project place has no name the game master command would recognise.

`is_open_world` matters because writing an offline character into an instance map
may produce a character who cannot log in — the server expects an instance
binding that does not exist.
