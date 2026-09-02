# Architecture

*wow-chat-neuron — the control plane for a running Everland Ghostsong world.*

## Position

neuron does not contain a game. It contains **operations**, and it points at a
**deployment** that does contain a game.

```
   ┌───────────────────────────────────────────────────────────┐
   │  wow-chat-neuron  (this project)                          │
   │                                                           │
   │   a sentence ──► the toolbox ──► an operation ──► a hand  │
   │                                                           │
   └───────────────────────────────────────────────────────────┘
                                │
                   points at, by config file
                                ▼
   ┌───────────────────────────────────────────────────────────┐
   │  a deployment  (wow-chat-2026, or any AzerothCore tree)    │
   │                                                           │
   │   worldserver ── SOAP :7878 ──┐                           │
   │   authserver                  │                           │
   │   MySQL ── unix socket ───────┤                           │
   │     acore_world_<profile>     │                           │
   │     acore_characters_<profile>│                           │
   │     acore_playerbots_<profile>│                           │
   │   lua_scripts/custom/ ────────┘  (ALE reads from here)    │
   └───────────────────────────────────────────────────────────┘
```

The deployment is named in `config/deployment.lua`. Nothing in neuron hardcodes
a path to wow-chat-2026; that project is merely the default target because it is
the one that exists.

**Consequence worth stating plainly:** neuron never compiles AzerothCore, never
applies a source patch, never installs a module, and never edits a `.conf`. If
a deployment lacks something neuron needs — the SOAP console being on, say —
neuron *detects and reports that*, and the fix happens in the deployment's own
project, where the tooling for it already lives.

## The Deployment Handle

Everything neuron does starts by resolving a deployment into a set of concrete
facts:

| Field              | Type   | Meaning                                              |
|--------------------|--------|------------------------------------------------------|
| `root`             | string | Absolute path to the deployment project directory    |
| `profile`          | string | Which profile is active (`vanilla`, `beta`, …)       |
| `mysql_socket`     | string | Unix socket path for the project-local MySQL         |
| `mysql_user`       | string | Database user                                        |
| `mysql_password`   | string | Read from the deployment's `secrets.conf`, never ours|
| `db_world`         | string | e.g. `acore_world_vanilla`                           |
| `db_characters`    | string | e.g. `acore_characters_vanilla`                      |
| `db_playerbots`    | string | e.g. `acore_playerbots_vanilla`                      |
| `soap_url`         | string | e.g. `http://127.0.0.1:7878/`                        |
| `soap_account`     | string | A game account with GM rank                          |
| `soap_password`    | string | That account's password                              |
| `lua_custom_dir`   | string | Where ALE loads custom scripts from                  |

The profile name is not chosen by neuron. It is read out of the deployment's
`.profile` file, because that is where the deployment already keeps the answer,
and two places holding the same answer is one place too many.

Database names are *derived* from the profile rather than configured, because
the deployment derives them the same way. If that convention ever breaks, the
derivation is one function in one file.

## Liveness Is a First-Class Fact

Every operation declares which hands it can use. Before any operation runs,
neuron establishes two booleans:

- **`db_up`** — the MySQL socket exists and accepts a connection.
- **`world_up`** — the SOAP endpoint answers.

These are not the same question and they do not have the same answer. A
deployment with the database up and the world down is the *normal* state for
bulk editing, and it is the only state in which some operations are safe.

The interesting case is the third combination:

| `db_up` | `world_up` | What can run                                          |
|---------|------------|-------------------------------------------------------|
| no      | no         | Nothing. Report which service is missing and stop.    |
| yes     | no         | Cold-hand operations only. Free rein on character rows.|
| yes     | yes        | Both hands — but cold-hand writes to *logged-in* characters are refused. |
| no      | yes        | Should not happen; the worldserver needs the database. Report it as a fault. |

That third row is the one that bites. A running worldserver holds every
logged-in character's state in memory and flushes it to the database on a timer
and at logout. A cold-hand `UPDATE characters SET position_x = …` against a
character who is logged in will be silently overwritten the moment the server
next saves that player, and the failure looks like "the tool didn't work"
rather than "the tool was ignored."

So the rule is mechanical, not advisory: **before any cold-hand write to a
character row, check whether that character is online.** With the world up, the
check is `characters.online = 1`. If it is set, the operation either routes to
the live hand instead or refuses with a message naming the character. It never
writes and hopes.

## The Three Hands

### The cold hand — SQL

Direct statements against the deployment's MySQL over its unix socket.

- **Reaches:** every row of every table. Character positions, inventories,
  group membership, skills, spells, levels, gameobject spawns, creature spawns.
- **Requires:** `db_up`.
- **Refuses:** writes to characters where `online = 1` (see above).
- **Visibility:** nothing is visible until something reads the row. For
  character rows that is the owner's next login. For world rows it is the
  next server start or an explicit reload command.

Every statement is built by a **parameterised builder**, never by string
concatenation of caller input. This is not only injection hygiene; it is what
makes an operation's SQL reviewable as a shape rather than as a string.

### The live hand — GM commands over SOAP

The worldserver's SOAP listener, turned on by the deployment
(`C021-soap-loopback-console.sh` in wow-chat-2026), bound to `127.0.0.1` only,
authenticated with HTTP Basic against a real game account holding GM rank.

The request is a SOAP envelope wrapping one command string — exactly the text a
GM would type after the dot. The response carries the console output the
command produced.

- **Reaches:** the entire GM command vocabulary AzerothCore ships. Teleport,
  summon, spawn gameobjects, modify level, add items, and several hundred more.
- **Requires:** `world_up`.
- **Visibility:** immediate, and visible to every player standing there.
- **Limits:** many GM commands act on the *selected* or *targeted* unit, which a
  SOAP caller does not have. Commands that take an explicit player name are
  usable; commands that only act on a selection are not, and the operation
  layer must not pretend otherwise.

That last limit is the main reason the cold hand exists at all.

### The resident hand — ALE Lua inside the worldserver

Scripts placed in the deployment's `lua_scripts/custom/` directory, loaded by
mod-ale, running inside the worldserver process on its tick budget.

- **Reaches:** live game objects as objects — a `Player`, a `Creature`, an
  event that just fired. It can *react*, which neither other hand can do.
- **Requires:** `world_up`, plus the script being present at load time (or a
  reload command).
- **Used for:** standing behavior. The garrison is the motivating case: holding
  a position, fighting, dying, respawning, and returning is a rule that keeps
  applying, not an edit that happens once.

neuron *writes* these scripts into the deployment's script directory and
triggers a reload. It does not run them; the worldserver does.

## An Operation

An operation is the unit of everything. It is a Lua table with a fixed shape,
and that shape is what both a human at a terminal and a model at the other end
of an HTTPS connection are talking to.

| Field         | Type     | Meaning                                                        |
|---------------|----------|----------------------------------------------------------------|
| `name`        | string   | Stable identifier, e.g. `character.teleport`                   |
| `summary`     | string   | One sentence, written for a reader who does not know the codebase |
| `params`      | table    | Ordered list of parameter descriptors (below)                  |
| `hands`       | table    | Which hands this operation can use, in preference order        |
| `reversible`  | boolean  | Whether an inverse receipt can be produced                     |
| `plan`        | function | `(deployment, args) -> steps`. Computes, touches nothing.      |
| `apply`       | function | `(deployment, steps) -> receipt`. Executes. Touches everything.|

A parameter descriptor:

| Field      | Type    | Meaning                                                    |
|------------|---------|------------------------------------------------------------|
| `name`     | string  | Parameter name                                             |
| `type`     | string  | One of `integer`, `number`, `string`, `boolean`, `list`, `roster`, `place` |
| `required` | boolean | Whether it must be supplied                                |
| `describes`| string  | What it means, in a sentence                               |
| `default`  | any     | Used when absent and not required                          |

### plan / apply is the whole safety model

The split is not decoration. `plan` is pure: it reads the database, resolves
names to GUIDs, computes coordinates, and returns a **list of steps** — each
step naming a hand and carrying either a fully-built SQL statement or a fully-
built command string. It changes nothing.

This buys three things at once:

1. **A dry run is free.** Run `plan`, print the steps, stop. There is no
   separate "simulate" code path that could drift from the real one, because
   the dry run *is* the real path minus its last line.
2. **The model's output is inspectable before it is real.** When a model
   chooses an operation and its arguments, what comes back is a plan. A person
   can read "these 14 UPDATE statements against these 14 named characters"
   before anything happens.
3. **Receipts are exact.** `apply` records what it actually did, step by step,
   including the previous value of anything it overwrote. That record is what
   makes an operation reversible.

## Receipts

Every `apply` returns a receipt, and every receipt is appended — never edited,
never deleted — to a log under the RAM-backed shared-memory tier, then rotated
into the repository when a session ends.

A receipt holds: the operation name, the resolved arguments, the deployment and
profile, wall-clock time, every step with its outcome, and — for any step that
overwrote a value — the value that was there before.

The prior-value capture is what makes `reversible` mean something. An
operation that moved forty characters can be undone because the receipt knows
where all forty of them were standing.

## The Toolbox

The toolbox is the set of all registered operations, and it exists in exactly
one form, from which two representations are derived:

```
   operations registry (Lua tables)
        │
        ├──► CLI surface        — one subcommand per operation,
        │                         parameters as flags, --plan for dry run
        │
        └──► tool-call schema   — one JSON tool definition per operation,
                                  params rendered as JSON Schema
```

Neither representation is written by hand. Adding an operation adds a
subcommand *and* a tool the model can call, because both are generated from the
same table. Two hand-maintained lists would drift, and the drift would show up
as the model calling a tool that no longer exists.

### The closed set

The tool-call schema is the complete list of what a model may cause to happen.
There is no `run_sql` tool, no `run_command` tool, no `bash` tool, no `eval`.
If the model wants something no operation expresses, the answer it gets is that
no operation expresses it — and the correct response to *that* is a person
writing a new operation, deliberately, in Lua, with a name.

This is the design position from the vision document, stated mechanically: the
model's reach is exactly the union of the registered operations' effects, and
that union is enumerable, reviewable, and small.

## Asking

Phase 8 adds one more entry point in front of the toolbox.

```
  a sentence
      │
      ▼
  ┌─────────────────────────────────────────────────────────┐
  │ POST https://api.anthropic.com/v1/messages              │
  │   model: claude-opus-5                                   │
  │   system: what the world is, what the operations are    │
  │   tools:  the generated schema (the closed set)         │
  │   messages: conversation so far                         │
  └─────────────────────────────────────────────────────────┘
      │
      ▼
  stop_reason?
      ├── "refusal"  ── report and stop; never read content
      ├── "end_turn" ── the model answered in prose; show it
      └── "tool_use" ── for each tool_use block: plan the operation
                             │
                             ▼
                        show the plan; apply it
                             │
                             ▼
                        ALL tool_result blocks in ONE user message
                             │
                             └──► loop
```

Mechanics that are easy to get wrong and are therefore written down here:

- **Model is `claude-opus-5`.** Thinking is on by default on this model; the
  `thinking` parameter is omitted rather than configured. `budget_tokens` is
  rejected outright with a 400 and must never appear.
- **`stop_reason` is checked before `content` is read.** A refusal returns HTTP
  200 with `stop_reason: "refusal"`; reading `content[0].text` first would
  produce a confusing error instead of a clear one.
- **Every `tool_result` for one assistant turn goes back in a single user
  message.** Splitting them across messages teaches the model to stop issuing
  parallel calls, which quietly halves throughput for no visible reason.
- **A failed operation returns a `tool_result` with `is_error: true`,** not a
  dropped block. The model is told what went wrong so it can choose differently.
- **Tool inputs are parsed as JSON,** never string-matched. Escaping in tool
  arguments varies and matching on the serialized form breaks unpredictably.
- **Server-side refusal fallback is on by default** for this model
  (`betas: ["server-side-fallback-2026-07-01"]` with `fallbacks: "default"`), so
  a classifier refusal routes to another model rather than dead-ending a
  request that was about moving game characters around.

Because Lua has no official Anthropic SDK, the transport is raw HTTPS with
hand-built JSON. That is a documented, supported way to use the API — it is
just more of neuron's own code, all of it confined to one file so the rest of
the project never sees a header.

## Where Things Live

```
wow-chat-neuron/
├── config/
│   └── deployment.lua        which world to point at
├── src/                      one counter, ascending, in reading order
│   ├── 000-deployment.lua    which world, and how to reach it
│   ├── 001-json.lua          encode and decode, for receipts and the API
│   ├── 002-cold-hand.lua     SQL over the deployment's own socket
│   ├── 003-live-hand.lua     GM commands over the SOAP console
│   ├── 004-liveness.lua      what is up, and what may therefore run
│   ├── 005-world-read.lua    rows become records
│   ├── 006-receipts.lua      the append-only record of what was done
│   └── ...                   later phases continue the same count
├── lua-resident/             scripts installed INTO the deployment (ALE)
├── docs/                     this directory
├── issues/                   blueprints, one per buildable thing
├── notes/                    vision and design writing
├── scripts/                  bash entry points
└── tmp/ -> /tmp/wow-chat-neuron
        └── shared-memory/ -> /dev/shm/wow-chat-neuron   (logs, receipts)
```

## Open Questions

These are not rhetorical. Each one changes what gets built, and each one is
waiting on an answer.

1. **Is "control plane, not a second server" the right call?** neuron currently
   assumes it attaches to a deployment it does not build. The alternative is
   that neuron eventually owns its own profile and build tree. Assumed, not
   decided.

2. **Who owns the GM account the live hand authenticates as?** It needs GM rank
   and its password ends up in a config file. Should neuron create a dedicated
   account for itself, or use an existing one named in configuration?

3. **Where do receipts finally live?** They are appended to the shared-memory
   tier while running, but that tier is RAM and does not survive a reboot.
   Rotating them into the repository makes them permanent and reviewable, and
   also means every character move is a tracked file change forever. Both
   readings are defensible.

4. **Should the resident hand be one script or many?** One script that reads a
   table of standing behaviors is simpler to reload; many scripts are easier to
   read in order. The file-index convention prefers many.

5. **What happens to a garrison when the server restarts?** The stated design
   says the watch ends when the server goes down. Whether it should be
   *restored* on the next boot — the bots log back in and walk back to the ridge
   — is unanswered, and it is the difference between a session-scoped feature
   and a persistent one.

6. **Does a plan expire?** A plan computed against a world where a character was
   at coordinate X, applied ten minutes later after they moved, is stale. Should
   plans carry a validity window, or re-verify at apply time?
