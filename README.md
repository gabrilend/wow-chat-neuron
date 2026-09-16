# neuron

A control plane for a running AzerothCore world.

You type a sentence, or a command. Something in the world changes: characters
move, creatures appear, a party is put back where it was standing an hour ago.
Every change is shown as a plan before it runs, and every change that runs is
written to a receipt that can put the world back.

neuron contains no game server. It attaches to an AzerothCore 3.3.5a
deployment you already run and operates on it from the outside, through the
database, through the game master console, and through Lua scripts it installs
into the server process.

```
scripts/neuron who 'bots hunters 18-20'
scripts/neuron teleport --roster 'bots hunters 18-20' --place ratchet --plan
scripts/neuron teleport --roster 'bots hunters 18-20' --place ratchet
scripts/neuron return --receipt 2026-09-06/013000-beef
```

```
> put four undead around level twelve near goldshire

PLANNED, NOT DONE.
  Rotting Ghoul (level 10-12) at Goldshire
  Rotting Ghoul (level 10-12) at Goldshire, 4 yards out
  Rotting Ghoul (level 10-12) at Goldshire, 6 yards out
  Rotting Ghoul (level 10-12) at Goldshire, 7 yards out
```

The chat window and the command line pull the same levers. A model, when one
is configured, pulls them too. It has no other tools: no shell, no SQL, no
file access. If an operation does not exist, the answer is that it does not
exist.

---

## Contents

- [How it reaches the world](#how-it-reaches-the-world)
- [Plan, then apply](#plan-then-apply)
- [What it can do](#what-it-can-do)
- [The menu](#the-menu)
- [Asking in plain language](#asking-in-plain-language)
- [Requirements](#requirements)
- [Getting started](#getting-started)
- [Everyday commands](#everyday-commands)
- [Where things are written](#where-things-are-written)
- [Security](#security)
- [Repository layout](#repository-layout)
- [Documentation](#documentation)
- [License and standing](#license-and-standing)

---

## How it reaches the world

Every operation declares which of three channels it can use, in order of
preference. neuron probes what is up before it runs anything, takes the first
channel that is available, and refuses by name when none is.

| Channel      | Mechanism                                                        | Needs                    | Reaches                                                                                         |
|--------------|------------------------------------------------------------------|--------------------------|-------------------------------------------------------------------------------------------------|
| **cold**     | SQL through the deployment's own `mysql` client                  | the database             | every row of every table. The only channel that reaches an offline character. Works with the worldserver down. |
| **live**     | game master commands over the worldserver's SOAP console         | the worldserver          | the whole GM command set AzerothCore ships. Instant, and visible to everyone standing there.    |
| **resident** | Lua scripts installed into `lua_scripts/custom/`, run by mod-ale | the worldserver, mod-ale | live game objects, in-process. The only channel that can react to events or create a creature that appears immediately. |

The distinction that matters most: a running worldserver holds each logged-in
character in memory and writes it back to the database on a timer and at
logout. A cold write to a logged-in character is silently overwritten. neuron
checks whether a character is online before every cold write and either
reroutes to the live channel or refuses. It never writes and hopes.

## Plan, then apply

Every operation is split in two. `plan` reads the world, resolves names to
rows and places to coordinates, and returns a list of steps. It changes
nothing. `apply` runs those steps and records what it did.

This gives three things at once:

- **A dry run is free.** Pass `--plan` on the command line, or read the plan
  the chat window shows you. There is no separate simulation path that could
  drift from the real one.
- **A model's choices are inspectable before they are real.** Inside a
  conversation, a change is only ever planned. What comes back is a list of
  readable lines and a question. You agree, and then it runs. Agreeing to the
  same plan twice is refused.
- **Receipts are exact.** Before any step overwrites a value, the previous
  value is read and stored. A receipt knows where all forty characters were
  standing, which is why `return` can put all forty back.

Receipts are append-only. Reads produce none, and reads never need agreement,
so a model can look at the world as many times as it likes while composing.

## What it can do

The vocabulary is a closed set of named operations with typed parameters.
Each is written once, as a declaration, and three surfaces are generated from
it: a command-line subcommand, a tool definition a model can call, and the
catalogue in `docs/vocabulary.txt`. An operation cannot exist as a command
without existing as a tool, and there is no tool a person cannot first try by
hand.

### Built and runnable

| Operation            | Does                                                                                                              | Channels        | Undo                     |
|----------------------|-------------------------------------------------------------------------------------------------------------------|-----------------|--------------------------|
| `world.creatures`    | Lists creature kinds by type, level band, name, or rank, for choosing something to spawn.                          | cold            | read                     |
| `character.teleport` | Moves a roster to a named place. Map and orientation are written with the coordinates, never without them.         | live, cold      | `character.return`       |
| `character.return`   | Reads a receipt and puts every character in it back where they were. Reports anyone who has moved since.          | cold            | itself                   |
| `character.retire`   | Moves characters into the game's own deleted queue. They vanish from every list and their names are freed.         | cold            | `character.restore`      |
| `character.restore`  | Brings characters back out of the deleted queue by the name they had going in.                                    | cold            | `character.retire`       |
| `world.spawn`        | Places creatures of a chosen kind at or near a named place, spread on a golden-angle spiral so they read as a group rather than a ring. Temporary by default. | resident, cold  | none yet                 |
| `world.announce`     | Says something to everyone logged in. A test lever, kept until the pipeline is proven and then deleted.            | live            | none needed              |
| `memory.forget`      | Lets a model drop one earlier part of its own conversation, by quoting it. The record is kept; only what is sent next time shrinks. | none            | none needed              |
| `character.purge`    | Permanently removes characters and every row that refers to them, using the same 39 statements the core itself runs. Takes a database backup first. Command line only, never offered to a model. | cold | none. Requires `--yes-remove-them`. |

Two parameter types do real work everywhere they appear:

- **A roster** is who. It is a character name, a comma-separated list of
  names, or a query: `bots hunters 18-20`, `bots`, `people`. Bots are
  recognised by the account-name prefix mod-playerbots gives them.
- **A place** is where. It is a name from the world's own `game_tele` table,
  the same 1,989 names the in-game `.tele` command accepts, so a name works the
  same through every channel. Ambiguous fragments are reported, not guessed.

### Designed

The full vocabulary is 43 operations across nine sections: displacement,
outfitting, company, renewal, construction, narration, and portage. It is
printed by `scripts/vocabulary` and read in `docs/vocabulary.txt`. The
roadmap in `docs/roadmap.md` groups it by what becomes true once each section
lands. The operations above are the ones that exist today; the rest are
declared at the level of name, channels, and parameters so the set makes sense
as a whole.

## The menu

`scripts/neuron-menu` starts a small web server on `http://127.0.0.1:7900`.
It is the front door, and it answers while everything else is down.

- **services**: whether MySQL, the authserver, and the worldserver are running,
  detected by the port each holds. Start and stop buttons for each, with a
  link to the log every launch writes. The worldserver's lamp stays amber for
  the half minute it spends loading map data.
- **chat**: every conversation, listed and revived from its transcript. A new
  conversation opens as the game master. Ask it for something; anything that
  would change the world comes back as a plan to agree to.
- **library**: every operation neuron knows, grouped by who can say it, with
  the reason an operation is unavailable when the deployment was built without
  the module it needs.
- **deployment**: the path neuron is pointed at, the profile it acts on, the
  game master account, and whether each was detected or set by hand.
- **model**: which model answers, a local bench model or a configured API, and
  a scripted setup conversation for when no model is running yet.
- **guide** and **server**: how to get AzerothCore built and neuron pointed at
  it.

The menu has no login. It binds to loopback unless you pass `--lan`, and it
says so out loud when you do.

## Asking in plain language

With a model configured, a sentence that neuron's own pattern grammar does not
recognise is handed to the model along with the tool schema generated from the
vocabulary. The model is told what the world is, including the level cap read
out of the deployment's own `worldserver.conf`, and which words exist.

- Reads run immediately and their results go straight back to the model.
- Changes are planned, never applied, from inside the loop. The plan's
  description is what the model receives as the result, and the plan waits for
  a person.
- Every tool result for one turn goes back in one message. A failed operation
  goes back as an error result with its reason, so the model can choose
  differently.
- A conversation is a plain text transcript, split into what people said and
  what the machinery said, stitched back together by section number when it is
  revived. Long conversations are trimmed with `scripts/neuron atoms`, or by
  the model itself through `memory.forget`.

Two backends are supported, selected in `config/asking.lua`:

| Backend      | Transport                                     | Meant for                                                         |
|--------------|-----------------------------------------------|-------------------------------------------------------------------|
| `configured` | the Anthropic Messages API, over `curl`       | running the world                                                 |
| `bench`      | a local Ollama server with a tool-capable model | building and testing, offline, for nothing                        |

Every reply says which one answered. Without an API key neuron can fall back to
the bench, loudly, or refuse; that is a setting, because quietly answering with
a much smaller model is worse than not answering.

## Requirements

- Linux. Port detection uses `ss` and `ip`.
- **LuaJIT** (2.1). All of neuron is Lua; there is no build step.
- **LuaSocket**. Used by the menu server and the database port probe.
- **curl**. Used to reach a model. Not needed to pull levers by hand.
- A **MySQL client binary**. neuron runs one rather than linking a driver. It
  looks for the deployment's own client first and can be pointed at any other.
- An **AzerothCore 3.3.5a deployment**, installed rather than only built, so
  that `worldserver.conf` and `authserver.conf` exist. Everything neuron needs
  to know about the deployment is read from those two files: database
  connections, ports, and the level cap.
- The worldserver's **SOAP console** enabled and bound to loopback
  (`SOAP.Enabled = 1` in `worldserver.conf`). Without it neuron works
  cold-channel only.
- Optional: **mod-ale** for the resident channel, which is what makes
  `world.spawn` appear immediately. **mod-playerbots** for bot recognition.
- Optional, for the test suite's page check only: `rhino` and `python3`.

A deployment laid out the way [wow-chat-2026](https://github.com/gabrilend/wow-chat-2026)
lays one out is detected automatically. That sibling project builds and runs a
customised AzerothCore with several profiles side by side, and it is the
default target only because it is the one that exists. A stock install with
its configuration under `env/dist/etc` is detected too. Anything else is
reached by naming the configuration directory outright.

## Getting started

1. **Clone.**

   ```
   git clone https://github.com/gabrilend/wow-chat-neuron.git
   ```

2. **Point it at your deployment.** Edit `config/deployment.lua` and set
   `root` to the absolute path of the directory holding your AzerothCore
   install. If your `worldserver.conf` is not under `installed-files-<profile>/etc`,
   `env/dist/etc`, or `etc/`, set `overrides.config_dir`. If the deployment
   does not ship its own MySQL client, set `overrides.mysql_client` to the
   path of one.

3. **See what it can reach.**

   ```
   scripts/status
   ```

   This names the deployment and profile, says whether the database and the
   worldserver answer, and when they do, counts characters, bots, and who is
   online. When something is down it says which service and what to do about
   it. This is the first thing to run whenever anything is not working.

4. **Give neuron a game master account.** In the worldserver console:

   ```
   account create neuron the-password
   account set gmlevel neuron 3 -1
   ```

   Then store the password, alone, in a file only you can read:

   ```
   mkdir -p secrets
   chmod 700 secrets
   printf '%s' 'the-password' > secrets/soap.key
   chmod 600 secrets/soap.key
   ```

   `printf '%s'` rather than `echo`, because `echo` appends a newline. A file
   readable by anyone else, or containing an `=`, or empty, is refused rather
   than warned about. Without this file neuron still reads and writes the
   database; nothing it does is visible in the game until the server next
   restarts.

5. **Pull a lever by hand.**

   ```
   scripts/neuron places ratchet
   scripts/neuron who 'bots hunters 18-20'
   scripts/neuron teleport --roster 'bots hunters 18-20' --place ratchet --plan
   ```

   Read the plan. Run it again without `--plan`. Then:

   ```
   scripts/neuron receipts
   scripts/neuron return --receipt <id> --plan
   ```

6. **Optionally, configure a model.** For the Anthropic API, put the key in
   `secrets/api.key` the same way as the SOAP key. For a local bench, run
   `ollama serve` with a tool-capable model pulled and set `bench.url` and
   `bench.model` in `config/asking.lua`. `use` selects which one answers;
   `when_unavailable` says what happens when it cannot be reached.

7. **Open the menu.**

   ```
   scripts/neuron-menu
   ```

   Visit `http://127.0.0.1:7900`. Start MySQL under services, wait for the
   lamp, then the authserver and the worldserver. Open a new conversation and
   ask it for something. Log in with the account you made, and watch.

## Everyday commands

Every script runs from any directory and accepts a different checkout as its
first argument.

| Command                          | Does                                                                                          |
|----------------------------------|-----------------------------------------------------------------------------------------------|
| `scripts/status`                 | What neuron is pointed at, what is up, and what may therefore run.                            |
| `scripts/neuron`                 | The command line. With no arguments, lists every subcommand. Any registered operation can also be called by its verb. |
| `scripts/neuron places <text>`   | Finds named locations to teleport to.                                                         |
| `scripts/neuron who <roster>`    | Resolves a roster and shows who is in it. Run this before anything that moves people.         |
| `scripts/neuron teleport`        | Moves a roster to a place. `--plan` to see the steps and stop.                                |
| `scripts/neuron return`          | Puts characters back from a receipt.                                                          |
| `scripts/neuron receipts`        | Shows what was done, filtered by date or operation.                                           |
| `scripts/neuron check`           | Finds rows naming characters that no longer exist. Exits non-zero when it finds any.          |
| `scripts/neuron retire`          | Permanently removes characters. Takes a backup first. Cannot be undone. This is `character.purge`, not the reversible `character.retire` a conversation offers. |
| `scripts/neuron atoms <id>`      | Shows the pieces a conversation is made of, and cuts some out of what is sent next time.      |
| `scripts/neuron-menu`            | Starts, stops, or restarts the web front door. `--port`, `--lan`, `--host`.                   |
| `scripts/transcript [id]`        | Lists conversations, or prints one stitched, one half at a time, or opens the real files.     |
| `scripts/vocabulary`             | Regenerates `docs/vocabulary.txt` from the declarations.                                      |
| `scripts/reading-order`          | Regenerates the source index in `docs/reading-order.md` from the file headers.                |
| `scripts/stubs`                  | Lists every placeholder in the project, asked of the code rather than searched for.           |
| `scripts/test`                   | Runs every test, checks that each page's JavaScript parses, and checks the generated documents are current. |
| `scripts/provision-profile`      | Gives neuron its own set of databases inside a wow-chat deployment's MySQL, copied from another profile. |

## Where things are written

| What                       | Where                                     | Survives a reboot |
|----------------------------|-------------------------------------------|-------------------|
| receipts                   | `tmp/shared-memory/receipts/`             | no                |
| service logs, menu log     | `tmp/shared-memory/`                      | no                |
| backups taken before purge | `tmp/shared-memory/`                      | no                |
| conversations              | `logs/asking/<date>/`                     | yes, untracked    |
| credentials                | `secrets/`                                | yes, untracked    |

`tmp/` is a symlink into `/tmp/wow-chat-neuron`, and `tmp/shared-memory/` a
further symlink into `/dev/shm/wow-chat-neuron`. Both are RAM. Every script
recreates the links before writing. A backup you want to keep has to be copied
somewhere durable by hand, and the purge command says so when it takes one.

## Security

- The model is handed a closed tool list. There is no `run_sql`, no
  `run_command`, no file write. Its reach is exactly the union of the
  registered operations, and that union is enumerable, reviewable, and small.
- Operations that cannot be undone take a confirmation parameter, which is what
  stops a model from reaching one in a single step. The permanent purge is in
  no model vocabulary at all.
- Every SQL statement is built by a parameterised builder. Caller input is never
  concatenated into a statement.
- Credentials live one per file, read at the moment of use, and never carried
  in a config table, a handle, an environment variable, or a command-line
  argument. A model may check that a key exists and how long it is, and may
  write one through plan-and-confirm. It can never read one.
- A model that can read the project's source for diagnosis is allow-listed to
  the source, documentation, and configuration directories. `secrets/`,
  `logs/`, and `tmp/` are not on the list.
- The menu is unauthenticated. Loopback is the default. Opening it to a network
  is a deliberate flag, and it means everyone who can reach the address can
  pull every lever.

## Repository layout

```
config/
  deployment.lua      which world to reach into, and how
  asking.lua          which model to hand a sentence to
src/                  one ascending index across the project, in reading order
  000-024             deployment, JSON, the cold and live channels, liveness,
                      reading the world, receipts, places, rosters, teleport,
                      return, purge, the bestiary, the command line
  025-enums/          hands, kinds, refusals, slots, stats, classes
  033-mechanisms/     the three channels behind one shape
  039-memory/         what a conversation holds, and how relevance decays
  041-vision/         cameras, and turning a pixel into a place
  045-toolbox/        the registry, and the tool schema drawn from it
  049-075             spawn, the API call, the loop, keys, HTTP, services,
                      the menu, transcripts, conversations, the deleted queue
tests/                one test per property; scripts/test runs them all
scripts/              the entry points listed above
assets/               the menu's pages
docs/                 architecture, roadmap, datapaths, the generated indexes
issues/               blueprints, one per buildable thing, grouped by phase
notes/                the vision document
secrets/              one credential per file, untracked
```

Source files are numbered so that reading them in order tells the story of how
a sentence becomes a change. `docs/reading-order.md` is the index.

## Documentation

- `notes/vision`: what this is and the one constraint that shapes it.
- `docs/architecture.md`: the three channels, why liveness is a first-class
  fact, the operation shape, receipts, and the toolbox.
- `docs/datapath-operation-dispatch.md`: the eight steps every operation is
  carried through.
- `docs/roadmap.md`: what gets built, grouped by what becomes true once it
  lands.
- `docs/vocabulary.txt`: the closed set, one line per word.
- `docs/table-of-contents.md`: every document, in a tree.

## License and standing

This is a private project, not affiliated with Blizzard Entertainment, and it
contains no game client, game data, or art. It attaches to
[AzerothCore](https://www.azerothcore.org/) (AGPL v3), and can use
[mod-playerbots](https://github.com/liyunfan1223/mod-playerbots) and
mod-ale, the AzerothCore Lua Engine, each under its own license.
The reasoning for building on this particular version of the game, and the
standing of what the project produces, is in `LICENSE.md`.
