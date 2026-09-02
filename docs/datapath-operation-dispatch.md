# Datapath — Operation Dispatch

*How a request becomes a change in a running world.*

This is the spine. Every other datapath document describes a particular
operation's `plan` and `apply`; this one describes the machinery all of them
are carried by.

## The Whole Path

```
  caller                     (a person at a terminal, or the API loop)
    │
    │  operation name + arguments
    ▼
  ┌──────────────────────────────────────────────────────────────┐
  │ 1. LOOKUP        registry[name] -> operation, or refuse      │
  └──────────────────────────────────────────────────────────────┘
    │
    ▼
  ┌──────────────────────────────────────────────────────────────┐
  │ 2. COERCE        each argument against its param descriptor   │
  │                  wrong type -> refuse, naming the parameter   │
  └──────────────────────────────────────────────────────────────┘
    │
    ▼
  ┌──────────────────────────────────────────────────────────────┐
  │ 3. RESOLVE       deployment handle: paths, db names, creds    │
  │                  liveness probe: db_up, world_up              │
  └──────────────────────────────────────────────────────────────┘
    │
    ▼
  ┌──────────────────────────────────────────────────────────────┐
  │ 4. HAND CHOICE   first hand in operation.hands that is up     │
  │                  none up -> refuse, naming what is down       │
  └──────────────────────────────────────────────────────────────┘
    │
    ▼
  ┌──────────────────────────────────────────────────────────────┐
  │ 5. PLAN          operation.plan(deployment, args) -> steps    │
  │                  reads freely. writes NOTHING.                │
  └──────────────────────────────────────────────────────────────┘
    │
    ├───────────────► --plan given? print steps. STOP HERE.
    │
    ▼
  ┌──────────────────────────────────────────────────────────────┐
  │ 6. GUARD         per-step safety checks                       │
  │                  cold-hand write to an online character?      │
  │                  -> reroute to live hand, or refuse           │
  └──────────────────────────────────────────────────────────────┘
    │
    ▼
  ┌──────────────────────────────────────────────────────────────┐
  │ 7. APPLY         execute each step in order                   │
  │                  capture prior value before each overwrite    │
  │                  a step that fails stops the run              │
  └──────────────────────────────────────────────────────────────┘
    │
    ▼
  ┌──────────────────────────────────────────────────────────────┐
  │ 8. RECEIPT       append to the receipt log; return it         │
  └──────────────────────────────────────────────────────────────┘
```

## Step 1 — Lookup

The registry is a plain Lua table keyed by operation name, populated at startup
by each operations file calling `registry.define{...}`. A dispatch table, not a
chain of comparisons — looking up a name should be one index, not a walk.

A name that is not present is a refusal, and the refusal names the closest
matches. This matters more for the model than for a person: when a model asks
for an operation that does not exist, the error text is the only thing telling
it what does.

## Step 2 — Coercion

Arguments arrive as strings from a terminal and as parsed JSON from the API.
Both are coerced against the same parameter descriptors, so an integer is an
integer by the time any operation sees it.

| Declared type | Accepts                                    | Becomes             |
|---------------|--------------------------------------------|---------------------|
| `integer`     | `42`, `"42"`                               | Lua number, floored |
| `number`      | `1.5`, `"1.5"`                             | Lua number          |
| `string`      | any string                                 | string              |
| `boolean`     | `true`, `"true"`, `"yes"`, `1`             | boolean             |
| `list`        | JSON array, or comma-separated string      | Lua array table     |
| `roster`      | a roster name, or a list of character names| resolved list of character rows |
| `place`       | a place-book name                          | `{map, x, y, z, o}` |

`roster` and `place` are the two that do real work. They turn a word a person
would say into rows and coordinates, and they do it in coercion rather than
inside each operation, so that every operation taking a roster resolves it the
same way.

A coercion failure is a refusal that names the parameter, the value it got, and
the type it wanted. It never guesses.

## Step 3 — Resolve

The deployment handle is built once and cached for the process. Building it
reads:

- `config/deployment.lua` — which deployment, by absolute path
- `<deployment>/.profile` — which profile is active
- `<deployment>/secrets.conf` — database credentials

and derives the three database names from the profile.

Liveness is probed here, not assumed:

- **`db_up`** — the MySQL socket path exists, and a trivial query returns.
- **`world_up`** — the SOAP endpoint answers a request.

Both probes have short timeouts and both record *why* they failed, because
"the socket file is missing" and "the socket exists but nothing is listening"
are different problems with different fixes, and the second one is what a stale
socket from a crashed server looks like.

## Step 4 — Hand Choice

Each operation declares `hands` as an ordered preference list, e.g.
`{"live", "cold"}` for teleport — prefer the live hand because it is instant
and visible, fall back to the cold hand when the world is down.

The dispatcher walks that list and takes the first hand whose liveness holds.
If none hold, it refuses and says which service is down and which one the
operation would have needed.

Note the ordering is per-operation and deliberate. Teleport prefers live.
Bulk relevelling of forty offline bots prefers cold, because forty GM commands
over SOAP is forty round trips and one `UPDATE ... WHERE guid IN (...)` is one.

## Step 5 — Plan

`plan(deployment, args) -> steps`

Pure. Reads the database, resolves names to GUIDs, computes coordinates,
decides what would have to happen. Returns an ordered list of steps.

A step:

| Field       | Type   | Meaning                                                     |
|-------------|--------|-------------------------------------------------------------|
| `hand`      | string | `cold`, `live`, or `resident`                               |
| `describes` | string | One line a person can read: "move Grast to Ratchet dock"    |
| `sql`       | string | For cold steps: the statement, with `?` placeholders        |
| `binds`     | table  | For cold steps: the values for those placeholders           |
| `command`   | string | For live steps: the GM command text, without the leading dot|
| `script`    | string | For resident steps: the Lua to install                      |
| `subject`   | table  | What this step acts on — `{guid, name, online}` if a character |
| `restores`  | table  | Filled in during apply: the prior value, for reversal       |

The `subject` field is what makes step 6 possible. A step that knows which
character it touches can be checked against that character's login state
without the guard having to parse SQL.

## Step 6 — Guard

The guard runs per step, immediately before it executes, not at plan time.
Plan-time state is stale by definition; the ten minutes between planning a move
and approving it are ten minutes in which someone can log in.

The check that matters:

```
  step.hand == "cold"
    and step.subject is a character
    and world_up
    and character is online
      -> this write will be silently overwritten when the server saves.
         Reroute to the live hand if the operation has a live form.
         Otherwise refuse, naming the character.
```

The failure mode this prevents is the nastiest kind: the statement succeeds,
the database changes, the tool reports success, and then the worldserver flushes
the in-memory copy over the top and the change evaporates. Nothing errors.
Somebody spends an afternoon on it.

## Step 7 — Apply

Steps execute in order. Before any step that overwrites a value, the prior value
is read and stored in `step.restores`. That read is the cost of reversibility
and it is paid on every write.

A step that fails **stops the run**. Remaining steps do not execute. The
receipt records what succeeded, what failed, and what was never attempted.

There is no automatic rollback of the steps that already succeeded. Rolling
back requires the same guards and the same liveness as going forward, and a
failed rollback inside a failed apply is a worse place to be than a partial
change with an exact record of itself. Reversal is a deliberate second
operation, driven by the receipt, run by someone who has read it.

## Step 8 — Receipt

Appended, never edited, to `tmp/shared-memory/receipts/<date>.log`, one JSON
object per line.

```
{ operation, arguments, deployment, profile, started, finished,
  steps: [ { describes, hand, outcome, restores } ],
  outcome: "complete" | "partial" | "refused" }
```

Append-only is not a stylistic choice. A receipt log you can edit is a receipt
log that cannot be trusted to tell you where forty characters used to be
standing, and that record is the only reason `character.return` can exist.

## Why plan and apply Are Separate Functions

Three reasons, in increasing order of how much they matter:

1. **A dry run costs nothing to maintain.** `--plan` is not a simulation mode
   with its own code path that can drift out of sync with the real one. It is
   the real path, stopped before its last step.

2. **A model's intent is inspectable before it is real.** When the API loop
   picks an operation and fills in arguments, what a person sees first is a
   list of sentences: "move Grast to Ratchet dock", "move Wenna to Ratchet
   dock", forty times. Reviewing that is possible. Reviewing a JSON blob of
   tool arguments is theoretically possible and practically not.

3. **The prior-value capture has somewhere to live.** Because apply walks a
   pre-built list of steps rather than discovering work as it goes, each step
   has a known subject before it runs, which is what lets the prior value be
   read and stored without every operation writing that logic itself.

## Failure Vocabulary

Failures are values, not exceptions, and there are exactly four kinds. Keeping
the set this small is what lets the API loop turn any failure into a
`tool_result` with `is_error: true` and useful text.

| Kind        | Means                                              | The caller should |
|-------------|----------------------------------------------------|-------------------|
| `unknown`   | No such operation, roster, place, or item list     | Use a different name; the message lists near matches |
| `argument`  | An argument was the wrong type or out of range     | Fix the argument; the message names it |
| `unavailable`| A required hand is down                           | Start the service, or wait |
| `refused`   | The operation could run but must not               | Read why; usually a character is online |

Per the project's standing position: a fallback is a warning and a warning is
an error. None of these four are recovered from silently. Every one is
reported, by name, to whoever asked.
