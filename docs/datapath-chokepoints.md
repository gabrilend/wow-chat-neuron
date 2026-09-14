# Datapath — The Gates

*Every place a request must pass through, and every place it changes hosts.*

The other datapath documents follow one kind of work from beginning to end.
This one is transverse: it lists the **narrow points**, the places where all the
possibilities converge to a single function or a single table.

The reason to care is control. A system with a hundred entry points can only be
guided by discipline. A system where everything must pass nine gates can be
guided by putting the check at the gate — validation, refusal, logging,
permission — once, where nothing can go around it.

Two kinds of narrow point, and they are different:

- **Gates** — one function every possibility passes through. Cheap to guard.
- **Crossings** — where data leaves one memory host for another. Expensive,
  lossy, and where types die.

---

## The Nine Gates

```
     a sentence, or a command line, or a tool call
                        │
   ┌────────────────────▼────────────────────────────────────┐
   │ 1  Load(path)              one instance per file        │
   ├─────────────────────────────────────────────────────────┤
   │ 2  Deployment.load()       one world, one set of creds  │
   ├─────────────────────────────────────────────────────────┤
   │ 3  Enum.of(text)           text becomes identity        │
   ├─────────────────────────────────────────────────────────┤
   │ 4  registry.of(name)       one word, or a refusal       │
   ├─────────────────────────────────────────────────────────┤
   │ 5  Schema.route(tool_use)  a model's call becomes a word│
   ├─────────────────────────────────────────────────────────┤
   │ 6  operation.plan()        intent becomes steps         │
   ├─────────────────────────────────────────────────────────┤
   │ 7  hold_plan()             a plan becomes agreeable-to  │
   ├─────────────────────────────────────────────────────────┤
   │ 8  MECHANISMS[hand]        a step becomes a change      │
   ├─────────────────────────────────────────────────────────┤
   │ 9  Receipts.write()        a change becomes a record    │
   └─────────────────────────────────────────────────────────┘
                        │
                   the world
```

### 1 — `Load(path)` · `src/024-load.lua`

Every module in the project, exactly once per process, memoised by normalised
path and kept single through `package.loaded`.

**Why it is a gate:** it is what makes gate 3 mean anything. An enum loaded
twice mints two sets of members that are not equal to each other, and every
identity comparison downstream silently returns false.

**What could be put here:** load timing, a manifest of what a run touched, a
refusal to load anything outside `src/`.

### 2 — `Deployment.load()` · `src/000-deployment.lua`

Which world, which profile, which databases, which credentials. Built once,
cached for the process.

**Why it is a gate:** nothing else in the project knows where anything is. A
function that wants the world database asks the handle. There is no second way
to find out, and no default — a missing config is fatal here rather than a
guess made further in.

**What is already here:** the refusal to guess a deployment, and the reading of
both secrets files so nothing above ever learns where a secret lives.

### 3 — `Enum.of(text)` · `src/025-enums/026-enum.lua`

The boundary where a string that names one of a closed set becomes a **member** —
a unique table. Inward of this point, comparison is by pointer.

**Why it is a gate:** it is the only place a spelling can be wrong. `"res"`
instead of `"resident"` is refused here, with the near match, rather than
routing to nothing three layers down. A member also carries which enum it came
from, so `Hands.holds(value)` can answer *is this one of mine* — a question a
string cannot be asked.

**Caught by it in practice:** the vocabulary sketch declared a hand named `res`,
found on the first run after the enums were wired in.

### 4 — `registry.of(name)` · `src/045-toolbox/047-registry.lua`

Every operation lookup, by name, one hash index.

**Why it is a gate:** a name not in the registry ends the request, so the
refusal is the only thing telling the asker what exists. It carries the other
words about the same subject first, then the whole set.

**What could be put here:** per-caller permission, rate limiting, an audit line
per word attempted rather than per word run.

### 5 — `Schema.route(registry, tool_use)` · `src/045-toolbox/048-schema.lua`

The model's side of the boundary. A `tool_use` block becomes an operation and a
table of arguments, or a refusal.

**Why it is a gate:** every single thing a model can cause passes through this
one function. There is no `run_sql`, no `bash`, no `eval` — the union of what a
model can do is exactly the registry, and this is where a call joins it.

Required arguments are checked here rather than inside the operation, so the
message can repeat the description the model already had and evidently did not
act on.

**Note the sibling control:** `Schema.tools(registry, filter)` decides what the
model is *offered*. A word absent from that list cannot be called by mistake, by
misunderstanding, or by persuasion — a stronger guarantee than asking it not to.

### 6 — `operation.plan(handle, args)`

Intent becomes an ordered list of steps. **Reads freely, writes nothing.**

**Why it is a gate:** it is the last point at which nothing has happened. Every
change in the project is computed here first, which is what makes `--plan` the
real path stopped one step early rather than a simulation that can drift.

### 7 — `hold_plan(server, plan, operation)` · `src/022-http-server.lua`

A computed plan goes into one table, keyed by id.

**Why it is a gate:** it is the only route from *proposed* to *agreeable to*.
Plans made by the hand-matched vocabulary and plans made by a model go into the
same store through the same function, so confirming either is one code path.
Two stores would eventually give two answers about whether something had already
run.

The plan is **removed as it runs**, whatever the outcome, because a plan
describes one moment and one that can run twice is how somebody sends a party to
the docks twice.

### 8 — `MECHANISMS[step.hand].perform(handle, step)` · `src/033-mechanisms/`

Every write to the world. One index into a table keyed on enum members.

**Why it is the most important gate:** nothing changes anywhere else. Cold, live
and resident all wear one shape, so the dispatcher never learns which it got —
and anything that must be true of every change to the world belongs here and
nowhere else.

**What is already here:** step validation against the hand's own `carries` list,
and the guarantee that a hand which raises still returns a value, so one bad
step cannot destroy the receipt for thirty-eight good ones.

### 9 — `Receipts.write(handle, receipt)` · `src/006-receipts.lua`

Append-only, one JSON object per line.

**Why it is a gate:** it is the only account of what happened, and the only
reason `character.return` can exist. A receipt log that could be edited is one
that cannot be trusted to say where forty characters were standing.

---

## The Crossings

A gate is cheap. A crossing costs a serialisation, and **types die at every
one.**

```
   Lua tables  ──┬──► MySQL socket ──► the mysql client's stdout ──► text
                 │         └── back as text, parsed to numbers where unambiguous
                 │
                 ├──► SOAP: an HTTP body of command text ──► the worldserver
                 │         └── back as PROSE, not as a status
                 │
                 ├──► generated Lua source ──► a file on disk ──► ALE's state
                 │         └── nothing comes back at all
                 │
                 ├──► JSON ──► a file on the RAM tier ──► curl ──► HTTPS
                 │         └── back the same way
                 │
                 └──► JSON, one line ──► the receipt log on the RAM tier
```

### Lua ↔ MySQL — `src/002-cold-hand.lua`

**Host:** neuron's process → a unix socket → the deployment's MySQL → the
`mysql` client's stdout → back as text.

**What is lost:** everything is text on the way back. Numbers are recovered
where unambiguous. A real `NULL` and a string whose value is the four characters
`NULL` are **indistinguishable** — stated as a known limit rather than papered
over.

**What guards it:** statements are shapes with `?` holes plus a separate list of
values. Callers never concatenate, so a name with an apostrophe cannot become
syntax.

### Lua ↔ worldserver — `src/003-live-hand.lua`

**Host:** neuron's process → HTTP to loopback → the worldserver's SOAP console.

**What is lost:** the answer is prose meant for a person. **A rejected command
comes back as HTTP 200 with an error sentence in the body**, so a caller
checking only the status believes it worked. This is the single most
counter-intuitive crossing in the project, and it recurs — the model API has the
same shape.

**What is impossible:** anything addressed by the caller's selection. A SOAP
caller has no body in the world, which is why `world.spawn` cannot use this hand
and why phase 6 places props through the database.

### Lua → the running world — `src/033-mechanisms/037-resident.lua`

**Host:** neuron's process → generated Lua **source text** → a file in the
profile's ALE directory → the worldserver's own Lua state.

**The only crossing whose effect outlives the call.** Everything else does one
thing and returns; a resident script stays and keeps running on the server's
tick.

**What is lost:** the return path entirely. The write is verified by reading the
bytes back; whether the script *compiled* is invisible — a syntax error installs
perfectly and never runs, which looks exactly like the feature not working.

### Lua ↔ a model — `src/050-api.lua`

**Host:** neuron's process → JSON → a file on `/dev/shm` → `curl` → HTTPS → back
through another file.

**Why through files:** a tool list plus a conversation is far past any safe
argument length, and **the key must never reach a command line** — anything in
an argument list is visible in `ps` to every user on the machine. Both are
deleted after.

**The trap, again:** HTTP 200 with an `error` object in the body is not a
success.

**The enum trap:** a member is an *empty proxy table*, so handing one to the
JSON encoder produces `{}` rather than `"cold"`. `Enum.name_of` is the crossing
for anything on its way out to text — a receipt, a body, a SQL bind.

---

## Where the gates are not yet closed

Honest gaps, each one a place something can currently go around:

- **Coercion is not a gate.** The datapath specification says a roster becomes
  rows and a place becomes coordinates before an operation sees them. Today each
  operation resolves its own inside `plan`, so two operations can drift apart in
  how they read the same roster. Issue 704.
- **The command line does not pass gate 4.** `020-cli.lua` still has seven
  hand-written subcommands that import operation files directly. Everything it
  does is correct and none of it is routed. Issue 702.
- **Reads mostly have no declaration.** Four of the CLI's commands are not in
  the registry at all, so a model can act on the world and can barely look at
  it. Only `world.creatures` has crossed over.
- **Nothing counts what passes.** Every gate above could report what went
  through it, and none does. The receipts log records what *changed*; there is
  no record of what was asked and refused, which is the difference between
  debugging a bad plan and guessing at one.
