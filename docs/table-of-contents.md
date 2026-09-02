# Documentation Table of Contents

Every document in `docs/` and `notes/` appears here. Issue files and source
code do not — issues are indexed by `issues/phase-N-progress.md`, and source is
indexed by `docs/reading-order.md`.

## Tree

```
wow-chat-neuron/
├── LICENSE.md                          Why an old version of WoW, and the standing
│
├── notes/
│   ├── vision                          What this project is and why      [start here]
│   └── wave-search-and-the-fanning-guard.md
│                                       A sparse, resumable spatial search, and
│                                       the guards who use it to take high ground
│
├── docs/
│   ├── table-of-contents.md            [this file]
│   ├── architecture.md                 The control plane, the three hands, the operation model
│   ├── roadmap.md                      Eleven phases, grouped by effect
│   ├── reading-order.md                Source files in narrative order
│   ├── balance-updates.md              Append-only log of knobs turned and levers pulled
│   │
│   ├── datapath-operation-dispatch.md  A request becoming a change — the spine
│   ├── datapath-displacement.md        Moving characters through space
│   ├── datapath-outfitting.md          Changing what characters own and wear
│   ├── datapath-company.md             Parties, bot generation, the garrison
│   ├── datapath-renewal.md             Levelling coherently, and the style vector
│   ├── datapath-construction.md        Placing geometry the map files never had
│   └── datapath-asking.md              The Claude API loop and the closed set
│
├── issues/
│   ├── phase-N-progress.md             One per phase; the development journey
│   ├── 1xx- .. 10xx-*.md               Blueprints, one per buildable thing
│   └── completed/                      Finished blueprints
│       └── demos/                      Phase demonstrations (part of the product)
│
├── src/                                Indexed for reading order
├── lua-resident/                       Scripts installed INTO the deployment
├── config/                             Which world to point at
├── scripts/                            Bash entry points
├── input/                              What goes into the box
├── output/                             What comes back out
├── desire/                             Notes on what should be better
├── faith/                              Expectation of boons and blessings
└── strategems/                         Dataflow patterns that keep proving useful
```

## Reading Order for a New Reader

1. **`notes/vision`** — what this is, and the one constraint that shapes it all
   (the model pulls levers; it does not write code).
2. **`docs/architecture.md`** — the three hands, and why liveness is a
   first-class fact rather than an assumption.
3. **`docs/datapath-operation-dispatch.md`** — the eight steps every operation
   is carried through.
4. **`docs/roadmap.md`** — what gets built, in order of foundation.
5. Whichever `datapath-*.md` covers the thing you are about to touch.

## The Datapath Documents

One per major feature, per project convention. Each answers the same three
questions for its feature: which tables and commands it touches, what its
`plan` computes, and what its `apply` actually does.

| Document | Covers | Phase |
|----------|--------|-------|
| `datapath-operation-dispatch.md` | Lookup, coercion, hand choice, plan/apply, receipts | 1, 7 |
| `datapath-displacement.md` | Teleport, rosters, the place book, return | 2 |
| `datapath-outfitting.md` | Item lists, strip, equip, loadouts, proficiencies | 3 |
| `datapath-company.md` | Groups, bot generation and retirement, the garrison | 4 |
| `datapath-renewal.md` | Relevelling, the style vector, style evolution | 5 |
| `datapath-construction.md` | Prop catalogue, placement, arrangements, spacing | 6 |
| `datapath-asking.md` | Tool schema generation, the conversation loop, approval | 8, 9, 10 |

## External References

- **`../wow-chat-2026/`** — the deployment this project points at, and the
  source of every pattern reused here. It is a sibling branch of the same
  repository, so any file of it is reachable with `git show main:<path>`.
- AzerothCore wiki — https://www.azerothcore.org/wiki/
- ALE (AzerothCore Lua Engine) API — fetched by `docs/ale/download.sh`
- LuaJIT reference — https://luajit.org/luajit.html
- Claude API — https://docs.anthropic.com/en/api/messages

## Adding a Document

1. Write it in `docs/`.
2. Add it to the tree above and, if it is a datapath document, to the table.
3. Commit.
