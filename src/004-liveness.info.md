# 004-liveness.lua

Combines the two hands' probes into one answer about what may run, and holds the
guard against this project's most damaging mistake.

## The mistake it prevents

A running worldserver holds every logged-in character's state **in memory** and
writes it to the database on a save timer and at logout. A cold-hand UPDATE
against a logged-in character succeeds, changes the row, reports success — and
is then overwritten by the server's next save of that player. Nothing errors
anywhere. The tool appears broken and the database appears correct.

## Functions

### `Liveness.probe(handle) -> state`
Asks both hands. Both probes always run even when the first fails, because
knowing that both are down is more useful than stopping at the first — it
distinguishes "nothing is started" from "one thing crashed".

`state` holds `db_up`, `db_reason`, `db_detail`, `world_up`, `world_reason`,
`world_detail`.

### `Liveness.fault(state) -> string | nil`
Detects the impossible combination: the world answering while the database does
not. A worldserver cannot run without its database, so this means a probe is
lying or neuron is pointed at a different deployment than it believes. Returns
an explanation; the caller must stop rather than warn.

### `Liveness.choose_hand(state, preference) -> hand | nil, why`
Takes the first hand in an operation's ordered preference list that is actually
up. Preference is per-operation: teleport prefers `live` because the change is
instant and visible; bulk relevelling of offline bots prefers `cold` because
forty GM commands is forty round trips and one UPDATE is one statement.

### `Liveness.guard_step(handle, state, step) -> verdict, why`
The guard. Verdict is `proceed`, `reroute`, or `refuse`.

Runs at **apply** time, not plan time. A plan reviewed for ten minutes is a plan
whose subjects had ten minutes to log in.

Returns `proceed` immediately for any step that cannot hit the failure mode: a
non-cold step, a step with no character subject, or any step at all when the
world is down (nothing is holding an in-memory copy to overwrite the row with).

### `Liveness.describe(state) -> string`
The matrix rendered for a person, with the one thing to do about each service
that is down.
