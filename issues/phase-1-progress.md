# Phase 1 — Reach: Progress

**Effect: the world is addressable.**

Point neuron at a deployment, learn what is running, and read a fact out of it.
Nothing in this phase changes anything.

## Where it stands

| Issue | Title | Status |
|-------|-------|--------|
| 101 | Deployment handle and configuration | Done, verified live |
| 102 | The cold hand — parameterised SQL | Done, verified live |
| 103 | The live hand — GM commands over SOAP | Written, untested — no worldserver running |
| 104 | Liveness probes and the hand-availability matrix | Done, verified live |
| 105 | Reading the world | Done, verified live |
| 106 | Receipts | Not started |
| 111 | The plain WotLK target platform | Not started; the work lands in the deployment |

The database was brought up and everything above except the live hand has now
been exercised against 25,015 real characters. The live hand still needs a
worldserver and a GM account password before it can be called anything.

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

**Bringing the database up found three things a stopped world could not.** The
probe paths had all been exercised; none of the reading had. Within minutes of
the socket answering:

The group reader was a syntax error. `groups` is a reserved word in MySQL 8, and
it had been backticked in one query and not the other. The statement looks
perfectly ordinary right up until the server refuses it, which is the whole
character of this class of bug — there is nothing to notice by reading.

The placeholder-count check caught its author. A draft left a duplicated query
in the summary with one placeholder and no values, and the bind step refused it
by naming both counts and printing the statement. It failed at the point of the
mistake rather than as a MySQL syntax error pointing at a character offset in a
string nobody typed, which is exactly what that check was written for.

And the deployment turned out to hold **three kinds of character, not two**.
24,110 bots, 5 people, and 900 characters with no account row whatsoever —
residue from bot fleets removed by deleting accounts without deleting their
characters. The first summary computed people as characters-minus-bots and
therefore reported 905 people on a server with one human account. That is what a
silent category error looks like from outside: not obviously broken, merely
surprising. Orphans are now their own count, the join that finds them is a LEFT
join so they cannot vanish, and the status board reports them as a warning
rather than a statistic, because residue nothing cleaned up is something
somebody should decide about.

That last one validates a phase-4 ticket a phase early. Issue 404 says "remove
generated bots and their rows, **completely**", and the emphasis was a guess when
it was written. Nine hundred rows say it was the right guess.

**A judgment call worth recording.** Bot detection reads the account-name prefix,
because nothing in the schema records that a character is a bot. It is a
heuristic and it is documented as one at the point where it is applied, rather
than being allowed to read as a fact. The prefix is configurable for the same
reason.

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
