# Phase 1 — Reach: Progress

**Effect: the world is addressable.**

Point neuron at a deployment, learn what is running, and read a fact out of it.
Nothing in this phase changes anything.

## Where it stands

| Issue | Title | Status |
|-------|-------|--------|
| 101 | Deployment handle and configuration | Done |
| 102 | The cold hand — parameterised SQL | Done |
| 103 | The live hand — GM commands over SOAP | Written, untested against a live server |
| 104 | Liveness probes and the hand-availability matrix | Done |
| 105 | Reading the world | Written, untested against a live database |
| 106 | Receipts | Not started |
| 111 | The plain WotLK target platform | Not started; the work lands in the deployment |

"Untested against a live server" is doing real work in that table. The deployment
this points at currently has neither its MySQL nor its worldserver running, so
the read layer and the live hand have been exercised only through their probe
paths. Both need a run against a live target before they can be called done.

## The journey

**The control-plane boundary held its first test.** The project's founding
assumption is that neuron attaches to a world it does not build. Issue 111 —
"we need a plain WotLK profile" — was the first thing that could have broken
that, and it did not: the answer was "then the deployment builds one", and
neuron's part is a line of configuration plus a validator. Worth noticing,
because the next such request will be easier to answer the same way.

**Deriving beat configuring, twice.** The profile is read from the deployment's
own `.profile` rather than configured in neuron, and the three database names
are computed from the profile rather than listed. Both were tempting to
configure and both would have created a second copy of an answer, whose failure
mode is silent writes to the wrong database. The handle resolved `vanilla` and
all three database names correctly on its first run without being told anything
except a directory.

**A bug that only a real target could reveal.** The database probe used
`io.open` to test whether the MySQL socket existed. It reported `socket_missing`
against a socket that was plainly there in a directory listing, because
`io.open` on a unix socket fails with ENXIO — a socket cannot be opened as a
stream. The bug collapsed the one distinction issue 104 says matters most: a
socket file left behind by a crashed MySQL exists and answers nothing, and
telling that apart from "MySQL was never started" is the difference between a
five-second diagnosis and a long one. `os.rename(path, path)` is the correct
test; it is a kernel no-op that succeeds for any path that exists, whatever kind
of file it is. The status board now correctly reports the deployment's stale
socket as stale.

**The live hand's command table earned itself immediately.** It records, per GM
command, whether the command takes an explicit character name or acts on the
GM's current selection — because a SOAP caller has no selection and can never
get one. Filling in the first eight entries turned up that `gobject add` is
selection-addressed, which means phase 6 cannot spawn props over SOAP at all and
must write `gameobject` rows through the cold hand. That is a phase-6 design
decision discovered in phase 1, for the cost of writing down a field.

## Open questions carried forward

From issue 101: whether neuron should ever address more than one deployment at
once, and whose `secrets.conf` should hold the SOAP password.

From issue 102: whether subprocess-per-statement is fast enough for a forty-step
plan, and whether reads and writes should use different database credentials so
that a `plan` is structurally incapable of modifying anything.

From issue 103: what GM rank the account actually needs, and whether the live
hand should rate-limit itself.

From issue 104: how stale a liveness probe may be, and whether a refusal should
ever be overridable.

From issue 105: whether a character record should cache within a dispatch.

None of these block phase 2.
