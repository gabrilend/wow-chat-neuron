# 202 — Rosters

## Status
- Phase: 2 (Displacement)
- Blocked by: 105 (reading the world)
- Blocks: 203 (teleport), 303 (equip), 402 (party assembly), 502 (relevel)

## Current Behavior

Nothing exists. Every operation that acts on more than one character would have
to invent its own way of being told which ones.

## Intended Behavior

A **roster** is a named set of characters, resolved at the moment it is used.

This is the lookup table the project was asked for: *"a teleport players script
which used a lookup table to teleport specific player id's toward a desired
location."* The roster is that table, and it is shared by every operation rather
than belonging to teleport.

### Four ways to say who

| Form | Example | Resolves to |
|------|---------|-------------|
| A list of names | `Grast,Wenna,Aalia` | Those characters |
| A saved roster name | `my-party` | Whatever that roster holds |
| A query | `bots level 18-20 hunters` | Everyone matching, right now |
| A group | `party of Grast` | That character's current party |

Resolution happens **at use time**, never at definition time. A roster defined as
"bots between 18 and 20" means different characters next week, and that is the
point — the alternative is a list that silently goes stale and moves the wrong
forty people.

### Resolution is one query

A roster of forty resolves in one round trip, not forty. This is the reason
`002-cold-hand.lua` exposes a placeholder-list builder and the reason
`005-world-read.lua` has list-shaped readers at all.

### Missing members are reported, never dropped

A roster naming forty characters that resolves to thirty-eight returns the
thirty-eight **and the two names that matched nothing**. An operation that moves
thirty-eight people and reports success is worse than one that refuses.

### Orphans are excluded by default

The live deployment holds 900 characters with no account row. They belong to
nobody and cannot be logged in. A query-form roster that did not exclude them
would sweep them into every bulk operation, and moving nine hundred abandoned
characters is a slow way to discover they exist.

Excluded by default, includable explicitly, and the exclusion is **reported** in
the resolution so it is never a silent filter.

## Suggested Implementation Steps

1. Write the resolver dispatch: a table from roster-form to resolver function,
   keyed on the shape of what was given.
2. Write the name-list resolver over the existing list reader.
3. Write the query resolver. Keep the query vocabulary small and boring —
   level range, class, race, bot-or-person, online-or-not, zone. It is a filter,
   not a language, and it should stay one.
4. Write the saved-roster store, with saved rosters holding a *definition*
   rather than a resolved list.
5. Write the group resolver over the existing group reader.
6. Write the resolution report: found, missing, excluded, and why.
7. Write `roster.show` so a person can see what a roster resolves to before
   handing it to something that moves people.
8. Write the `.info.md`.

## Open Questions

- **Can a roster contain another roster?** Composition is obviously useful and
  obviously how you get a cycle. Either forbid it or detect the cycle; do not
  discover it at a depth of forty.
- **Should a saved roster be able to pin?** "The forty bots I moved yesterday"
  is a real thing to want and is the opposite of resolve-at-use-time. A receipt
  already records exactly that set, which may make this unnecessary.
- **How large may a roster be before it needs confirming?** Twenty-five thousand
  characters exist. A query roster with a typo in its filter could resolve to all
  of them. There should be a size above which the operation stops and asks.

## Related

- `docs/datapath-displacement.md`
- Issue 105 — the readers this is built on, and the orphan finding
- Issue 203 — teleport, the first consumer
