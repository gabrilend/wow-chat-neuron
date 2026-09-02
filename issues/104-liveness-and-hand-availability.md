# 104 — Liveness Probes and the Hand-Availability Matrix

## Status
- Phase: 1 (Reach)
- Blocked by: 102 (cold hand), 103 (live hand)

## Current Behavior

Each hand can probe itself, but nothing combines the two answers into a
decision about what may run.

## Intended Behavior

One function answers, for a given deployment, which hands are usable right now
and why — and one guard uses that answer to stop the single most damaging
mistake this project can make.

### The matrix

| `db_up` | `world_up` | What can run |
|---------|------------|--------------|
| no | no | Nothing. Name the service that is down and stop. |
| yes | no | Cold-hand operations only. Free rein on character rows. |
| yes | yes | Both hands — but cold-hand writes to *online* characters are refused or rerouted. |
| no | yes | Should be impossible; the worldserver requires the database. Report as a fault rather than proceeding. |

That last row deserves the word "fault". If it is ever observed, something is
wrong with the probe or the deployment is not what neuron thinks it is, and
both are worse than a service being down.

### The guard

The third row is the one that costs afternoons.

A running worldserver holds every logged-in character's state **in memory**. It
writes that state to the database on a save timer and at logout. A cold-hand
`UPDATE characters SET position_x = ...` against a character who is logged in
succeeds, changes the row, reports success — and is then overwritten by the
server's next save of that player. Nothing errors. The tool appears broken.

So before any cold-hand step whose subject is a character, with the world up:

- Read that character's `online` column.
- If online and the operation has a live form, **reroute the step to the live
  hand**.
- If online and it does not, **refuse**, naming the character and saying why.
- Never write and hope.

The check happens at apply time, not plan time. A plan reviewed for ten minutes
is a plan whose subjects may have logged in during the review.

### Reporting

A probe result is not a boolean. It carries the reason, because the fixes
differ and the person reading it should not have to guess:

| Reason | Means | Fix |
|--------|-------|-----|
| `socket_missing` | No socket file at the expected path | Start the deployment's MySQL |
| `socket_stale` | Socket file exists, nothing listening | A crashed server left it; start MySQL |
| `auth_failed` | Connected, credentials rejected | Fix the credentials |
| `connection_refused` | Nothing listening on the SOAP port | Start the worldserver, or SOAP is disabled |
| `soap_unauthorized` | Answered with 401 | Wrong SOAP account or password |
| `up` | Answered correctly | — |

`socket_missing` and `socket_stale` being distinguishable is the whole reason
this table exists. The stale socket left behind by a crashed MySQL is the
single most confusing state a deployment gets into, and the difference between
"there is no socket" and "there is a socket and it is a lie" is the difference
between a five-second diagnosis and a long one.

## Suggested Implementation Steps

1. Write the probe combiner: call both hands' probes, return a table with both
   booleans and both reasons.
2. Write the availability function: given an operation's `hands` preference list
   and a probe result, return the hand to use, or a refusal naming what is down.
3. Write the online-character guard as a standalone function taking a step and a
   probe result, returning `proceed`, `reroute`, or `refuse` with a reason.
4. Write the fault detection for the impossible row and make it say "fault", not
   "warning".
5. Write a status command that prints the matrix for the configured deployment
   in human-readable form. This is the observable half of phase 1 and the thing
   the phase demo is built around.
6. Write the `.info.md`.

## Open Questions

- **How stale may a probe be?** Probing once per process is cheap and can be
  wrong by the end of a long plan. Probing per step is correct and slow. A
  short cache with a re-probe before the first write of each hand is probably
  the right shape, but "probably" is not an answer.
- **Should a refusal be overridable?** There are legitimate reasons to write to
  an online character's row — you might be about to kick them. An explicit
  `--anyway` flag would allow it and would also be the first thing anyone
  reaches for when confused. Leaning against, for now.

## Related

- `docs/architecture.md` — Liveness Is a First-Class Fact
- `docs/datapath-operation-dispatch.md` — steps 4 and 6
