# 102 — The Cold Hand: Parameterised SQL Against the Deployment

## Status
- Phase: 1 (Reach)
- Blocked by: 101 (deployment handle)

## Current Behavior

Nothing exists. There is no way to read or write a row in the deployment's
databases.

## Intended Behavior

A module that runs SQL against the deployment's project-local MySQL over its
unix socket, returning rows as Lua tables, and that refuses to build a
statement by pasting caller input into a string.

### Transport

The deployment ships its own MySQL binaries and its own socket. The connection
uses that socket, that binary, and the credentials from the handle. Nothing
touches the system-wide MySQL, which on this machine is a different instance
serving different data — connecting to the wrong one is a real and easy
mistake, and the socket path is what prevents it.

Because LuaJIT has no bundled MySQL driver and the project avoids package
managers, the first implementation invokes the deployment's own `mysql` client
as a subprocess and parses its output. This is a deliberate trade: it is slower
per statement than a native driver and it is immune to driver-version skew with
whatever MySQL the deployment happens to ship.

Output is requested in a machine-readable form rather than the default aligned
table, because parsing column-aligned ASCII is how you eventually mangle a
character named `Grast  Two`.

### Parameterisation

Statements carry `?` placeholders and a separate list of bind values. The
module substitutes them, escaping each value according to its Lua type:

| Lua type | Rendered as |
|----------|-------------|
| number | the literal, integer-floored where the column is integral |
| string | single-quoted, with backslash and quote escaped |
| boolean | `1` or `0` |
| nil | `NULL` |

Callers never concatenate. An operation that wants forty GUIDs in an `IN`
clause asks for a placeholder list of length forty and passes forty binds.

This is injection hygiene, but that is the smaller half. The larger half is
that a statement written as a shape with holes is **reviewable as a shape** —
a person reading a plan sees `UPDATE characters SET position_x = ? WHERE guid = ?`
and forty pairs of values, which is comprehensible, rather than forty complete
statements, which is not.

### Reads and writes are different functions

- A read returns an array of row tables, keyed by column name, with values
  already converted to Lua types. An empty result is an empty array, never nil
  — a caller iterating a result set should not have to nil-check first.
- A write returns the affected-row count. A write that affects zero rows when
  it was expected to affect some is a condition the *caller* judges, not the
  transport; the transport reports the number and stays out of it.

## Suggested Implementation Steps

1. Write the escaper first and test it against the values that break naive
   implementations: an apostrophe in a name, a backslash, an embedded newline,
   an empty string, a very large integer.
2. Write the placeholder substitution, which walks the statement and the bind
   list together and errors when their counts disagree. A count mismatch is a
   programming error in an operation, and it should surface at the point of
   mismatch rather than as a MySQL syntax error later.
3. Write the subprocess invocation against the deployment's `mysql` binary,
   with the socket, user, password, and database from the handle.
4. Write the result parser for the machine-readable output format, converting
   the empty-field marker back to nil and numeric columns to numbers.
5. Write the liveness probe: does the socket file exist, and does a trivial
   query return? Two separate answers, because a socket file left behind by a
   crashed server exists and answers nothing.
6. Write the `.info.md`.

## Open Questions

- **Is subprocess-per-statement fast enough?** A forty-step plan is forty
  process spawns. If that proves too slow, the fix is batching statements into
  one invocation, which the step list already makes possible since it is built
  before anything runs. Measure before optimising.
- **Should reads and writes use different credentials?** A read-only user for
  planning and a read-write user for applying would make it structurally
  impossible for a `plan` to modify anything, rather than merely conventional.
  Attractive; not yet required.

## Related

- `docs/architecture.md` — the cold hand
- `docs/datapath-operation-dispatch.md` — step 7, Apply
- Issue 104 — the liveness probe this issue provides half of
