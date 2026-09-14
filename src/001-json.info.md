# 001-json.lua

Encode and decode JSON. Written here rather than depended on, because the project
takes no package-manager dependencies and needs only the subset receipts and the
Claude API use.

## Functions

### `Json.encode(value, indent) -> string`
`indent` (e.g. `"  "`) turns on pretty-printing. Receipts encode **without**
indent — one object per line, so a line is a record and the log is append-only in
the strict sense.

Errors on NaN and infinity rather than writing `null`. A null where a coordinate
should be is a character who cannot be put back, and nothing saying so.

**Object keys are sorted.** Not tidiness: unsorted keys make two encodings of the
same data differ byte-for-byte, which breaks comparison, checksums, and — in
phase 8 — prompt caching, whose entire mechanism is a byte-exact prefix match.

Numbers: integers print as integers, everything else with 17 significant digits,
which is what a double needs to round-trip exactly. A position of -3827.93 must
come back as -3827.93 and not -3827.9; a few yards is the difference between a
ledge and the ground below it.

### `Json.decode(text) -> value | nil, why`
Errors are **returned, not thrown** — the main consumer is a network response,
where malformed is an ordinary event to report rather than an exceptional one to
crash on.

### `Json.array(list)`
A sentinel that encodes as `[]`. Lua cannot distinguish an empty array from an
empty object, and guessing is how a tool call arrives with `{}` where the API
wanted `[]`.

## Known limits

- `null` decodes to `nil`, so a key whose value was null **vanishes** from the
  decoded table. A caller distinguishing "absent" from "explicitly null" cannot
  do it after decoding.
- Surrogate pairs are not recombined. A character above the basic plane arrives
  as two escapes and comes out as two three-byte sequences. Nothing this project
  reads has contained one; pretending otherwise would be worse than saying so.
