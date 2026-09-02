# 002-cold-hand.lua

SQL against the deployment's own MySQL, over its own socket, using its own
client binary. The hand that works when the world is **down**.

Statements are shapes with `?` holes plus a separate list of values. Callers
never concatenate.

## Functions

### `ColdHand.read(handle, database, statement, values) -> rows | nil, why`
Runs a SELECT. `rows` is an array of tables keyed by column name, with values
already converted to Lua numbers where unambiguous. **An empty result is an
empty array, never nil** — a caller looping a result set should not have to
nil-check first. Only a genuine failure returns nil.

### `ColdHand.write(handle, database, statement, values) -> affected | nil, why`
Runs a statement that changes rows. Returns the affected-row count. Zero is
reported as zero and is **not** treated as an error here; whether zero is wrong
is the caller's judgment.

### `ColdHand.bind(statement, values) -> string`
Substitutes `?` placeholders with escaped values, left to right. Errors when the
placeholder count and value count disagree, naming both counts — that is a
programming error in an operation and it surfaces at the point of the mistake.

Value rendering: nil → `NULL`, boolean → `1`/`0`, integral number → integer
literal (never scientific notation, so a GUID matches), other number → 17
significant digits (lossless round trip), string → quoted with backslash,
quote, newline, and control characters escaped.

### `ColdHand.placeholders(count) -> string`
Builds `"?, ?, ?"` for an IN clause. Errors on 0, because an empty IN clause is
not valid SQL and the caller should skip the query entirely. Exists so a roster
of forty is one round trip rather than forty.

### `ColdHand.probe(handle) -> up, reason, detail`
Is the database reachable? `reason` is one of `up`, `socket_missing`,
`socket_unreadable`, `socket_stale`, `auth_failed`.

`socket_missing` and `socket_stale` are distinguished on purpose: a socket file
left behind by a crashed MySQL exists and answers nothing, which is the single
most confusing state a deployment gets into. Existence is tested with
`os.rename(path, path)`, not `io.open` — `io.open` on a live unix socket fails
with ENXIO and would report every stale socket as missing.

## Known limit

In the client's batch output, a real NULL and a string whose value is the four
characters `NULL` are indistinguishable. This does not bite for anything neuron
reads. A column that must hold the literal text "NULL" cannot be read this way.
