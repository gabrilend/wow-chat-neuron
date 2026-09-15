# 113 — Published Credentials: Refusing to Go Public With a Known Password

## Status
- Phase: 1 (Reach)
- Blocked by: 101a (which built the reader that already knows the real credentials)
- **Blocks: the server being reachable from outside this machine.** This is the
  point of the ticket. Nothing else in the project is gated on it, and this one
  thing is.

## Current Behavior

The deployment's MySQL account — user `ritz`, password `menardi`, port 3307 — is
written in plain text in files tracked by git in **both repositories, and both
repositories are public.** Confirmed rather than inferred: an anonymous
`git ls-remote` with the credential helper disabled returns refs for
`gabrilend/wow-chat-neuron` and `gabrilend/wow-chat-2026` alike.

wow-chat-2026 has carried it since its first commit, `3bd871e`, dated
2026-01-28. So this is not a credential that is *about* to be published. It is
one that has been readable for months, and no rewriting of history changes that
— a published credential is published from the moment somebody fetches it, not
from the moment somebody notices.

Where it is, in this repository:

| File | What it is |
|------|------------|
| `CLAUDE.md` | the project instructions, stating the credentials outright |
| `issues/101a-one-deployment-shape.md` | the worked example of a parsed `LoginDatabaseInfo` line |
| `src/073-server-config.lua` | a comment showing the five-field format |
| `tests/073-server-config.test.lua` | the fixtures the reader is tested against |
| `llm-transcripts/` | a dozen places, including the `CREATE USER` statement |

And in wow-chat-2026, which is a separate repository and has its own copy of this
problem:

| File | What it is |
|------|------------|
| `config/patches/C001-database-connections.sh` | writes the password into five generated config files |
| `config/patches/C011-realmlist-setup.sh` | the password, and the realm's real hostname `wow.ritzmenardi.com` |
| `patches/E-patches.sh` | passes it on a `mysql` command line |
| `scripts/generate-148j-pretrain-sql` | the same |
| `scripts/azerothcore-deprecated` | the same, plus the `CREATE USER` that set it |

**Today this costs nothing.** MySQL is bound to `127.0.0.1` and the realm is not
reachable. A password that only opens a door nobody can walk up to is not a
secret that has leaked; it is a string.

**The day the server is reachable, it is a password on the internet** — one that
was on the internet before anybody typed it, indexed, in a public repository,
next to the port it opens and the username it belongs to. And by then it will not
be one decision anybody remembers making. It will be the accumulated result of a
realm being switched on.

That gap between "costs nothing" and "costs everything", with no event in between
to notice, is what this ticket is for.

## Intended Behavior

**neuron refuses to describe a deployment as reachable-ready while any credential
it can see is one that has been published.**

Not a warning. A warning is an error here, and an error nobody is forced past is
a comment. The refusal names the credential, names where it is published, and
says what to do instead.

neuron is the right thing to hold this, and it is the only thing that can. It
already reads the deployment's real credentials out of the server's own
configuration — that is what 101a built, and the reason it was built was so that
neuron stops guessing and starts knowing. The other half, the set of strings that
are published, is small, closed, and belongs in the source next to the check.

### What it knows, and how

| Half | Where it comes from |
|------|---------------------|
| the credentials actually in use | `src/073-server-config.lua`, which parses `host;port;user;pass;db` out of `authserver.conf`, `worldserver.conf` and `playerbots.conf`, and carries the file and line each value came from |
| the credentials known to be published | a closed list in the new source file, one entry per published string, each saying which repository published it |
| whether the deployment is exposed | the bind addresses and ports the same reader already extracts: `SOAP.IP`, `RealmServerPort`, `WorldServerPort`, and the database host |

The three combine into one answer per credential: *this password is published,
this port is bound to something other than loopback, therefore this deployment
must not be switched on.*

### Where it surfaces

- **The front door.** `src/059-menu.lua` already draws a row per service saying
  whether it is running and offering to start it. A service whose credentials are
  published gets a refusal in place of its start control, with the reason.
- **The status board.** `scripts/status` prints what neuron can see; a published
  credential is one of the things it can see.
- **Before anything binds a public address.** The check is cheap and reads files
  that are already open.

### What it is not

It is not a secret scanner and must not become one. It answers one question about
one closed list, and a list of five strings that is right is worth more than a
pattern-matcher that is nearly right — a scanner that cries wolf on every
`password =` in a config file teaches people to pass it, which leaves the project
worse off than having no check at all.

## Suggested Implementation Steps

1. **Write down what is published, and where.** A new source file holding the
   closed list: each entry a string, the repository that published it, and the
   file in that repository a reader can go and look at. This is the part that
   must be right; everything else is arithmetic on it.

2. **Ask the reader for the credentials in use.** `src/073-server-config.lua`
   already returns them with provenance. No new parsing — if something needs
   parsing that this does not already do, that is a change to 073, not a second
   reader.

3. **Decide what "exposed" means, and write the decision down.** A database on
   `127.0.0.1` is not exposed. A realm port on `0.0.0.0` is. The SOAP console
   bound to loopback is not, even though it authenticates with a game account.
   The distinctions are few and each needs a sentence saying which way it falls
   and why, because the next person to read this will have a case that is not
   obviously either.

4. **Make the refusal a refusal.** Use the existing kinds — `src/025-enums/029-refusals.lua`
   has four, and this is one of them. It returns a refusal value like everything
   else; it does not raise, and it does not print and continue.

5. **Put it in front of the menu's start controls** (`src/059-menu.lua`) **and in
   the status board** (`scripts/status`).

6. **Test the three cases that matter:** a published password on a loopback-only
   deployment (allowed, and says so), a published password on an exposed one
   (refused, naming both halves), and an unpublished password on an exposed one
   (allowed). The middle case is the one the ticket exists for and the one that
   will never happen during development, so it only ever exists as a test.

7. **Then change the password, and delete its entry from the list.** The check
   staying green afterwards is the proof that the change actually reached the
   running server rather than only the files.

## Related Documents and Tools

- `src/073-server-config.lua` and its `.info.md` — the reader that already knows
- `src/052-keys.lua` — credentials as files pointed at rather than values carried;
  the shape the replacement password should arrive in
- `src/025-enums/029-refusals.lua` — the four kinds of no
- `src/054-stubs.lua` — the other standing announcement in this project, and the
  model for how this one should read at the point of use
- `issues/101a-one-deployment-shape.md` — why neuron reads the server's own config
- `secrets/README.md` — why a credential lives in its own file

## Open Questions

These are unanswered and this ticket is not finished while they are.

1. ~~**Does changing the MySQL password belong to neuron or to wow-chat-2026?**~~
   **Answered: the other project, and it has a ticket.** The account is created
   there and written into generated configs by a config patch there, so neuron
   can see the problem and cannot fix it. wow-chat-2026's issue 107 —
   originally *"Credential Manager Script"*, filed in April and overtaken twice
   since — now carries the rotation. **This ticket detects; that one rotates.**
   Neither is finished until both are.

2. **What about the realm hostname?** `wow.ritzmenardi.com` is published in the
   same file as the password. A hostname is not a credential and does not rotate.
   Is publishing it a problem to solve, a thing to accept, or a reason to move
   the realm to a name that was always meant to be public?

3. ~~**Do the transcripts count?**~~ **Answered: no, and they must not be
   touched.** The password is being rotated, so what the transcripts carry is a
   dead string, and a dead password in a record of what was said is a fact about
   the past rather than a secret. Scrubbing them would mean editing the record
   to make the past agree with the present, which is the one thing this project
   has said repeatedly it will not do.

   They also *cannot* be edited in the ordinary way: a transcript is not written
   by hand, it is rendered from a Claude session log by
   `scripts/backup-conversations` in the shared tooling, which the harness runs
   after **every turn**, in every project. An edit survives until the end of the
   turn that made it. Editing the renderer instead would rewrite every transcript
   in every project at once.

4. **What does the check do about a deployment it cannot read?** A stock
   AzerothCore that neuron has been pointed at may have credentials neuron has no
   list for. Silence is the wrong answer and so is a refusal. What is the third
   thing?

5. **Is there a moment to hook that is more honest than "the menu draws a start
   button"?** The real event is a port binding to a public address, which happens
   inside the worldserver, not inside neuron. Is a check that runs beforehand
   good enough, or is this eventually a thing the resident hand watches?
