# 103 — The Live Hand: GM Commands Over the SOAP Console

## Status
- Phase: 1 (Reach)
- Blocked by: 101 (deployment handle)

## Current Behavior

Nothing exists. There is no way to make a running worldserver do something.

## Intended Behavior

A module that sends one GM command to the running worldserver and returns what
the console printed back.

### What this rides on

AzerothCore's worldserver has a built-in SOAP listener. The sibling project
turns it on and pins it to loopback in `config/patches/C021-soap-loopback-console.sh`:
enabled, bound to `127.0.0.1`, port `7878`. It authenticates with HTTP Basic
against a real game account, and the account must hold GM rank for its commands
to be accepted.

neuron consumes that. It does not enable SOAP, does not edit the deployment's
config, and does not assume it is on — it *probes*, and reports clearly when it
is off, because "the world is running but SOAP is disabled" is a configuration
state a person can fix in thirty seconds if they are told that is the problem.

### The request

A SOAP envelope wrapping a single command string — the exact text a GM would
type after the dot, without the dot. `tele name Grast ratchet` rather than
`.tele name Grast ratchet`.

The response body carries the console output. That output is the operation's
evidence that something happened, and it is captured into the receipt verbatim.

### The limit that shapes everything above it

A large part of the GM vocabulary acts on the **currently selected unit**.
A SOAP caller has no selection and cannot make one. So:

- Commands taking an explicit character name are usable.
- Commands acting only on a selection are **not usable at all** through this
  hand, and the module must not paper over that.

This single constraint is the reason the cold hand exists. Where no
name-taking command exists for something, the database is the only route.

The module therefore keeps a list of the commands neuron actually uses, each
recorded with whether it takes a name or needs a selection, so an operation
declaring a live step is checked against reality at registration time rather
than failing at a player's expense.

### Errors

A GM command that fails usually returns HTTP 200 with an error sentence in the
body, not an HTTP error code. Detecting failure means reading the body, not
checking the status. The module returns the body and a judgment; operations
decide what a given failure means for them.

## Suggested Implementation Steps

1. Write the envelope builder — the SOAP wrapper, with the command XML-escaped
   into it. A character name containing an ampersand should not produce
   malformed XML.
2. Write the HTTP POST with Basic auth. Lua has no bundled HTTP client, so this
   is either a socket library or the system `curl` as a subprocess; prefer
   whichever the transport in issue 801 will also use, so there is one HTTP
   path in the project rather than two.
3. Write the response reader — unwrap the envelope, extract the console text,
   and un-escape it.
4. Write the liveness probe: does the endpoint answer at all? Distinguish
   "connection refused" (world down, or SOAP disabled) from "401" (credentials
   wrong) from "answered" — three different fixes.
5. Write the command table: name, whether it takes a character name, one line
   on what it does. Start with only what phases 2–6 actually need and grow it
   deliberately; a complete transcription of AzerothCore's command list would be
   a large document that is mostly wrong within a year.
6. Write the `.info.md`.

## Open Questions

- **What GM rank does the account need?** Different commands sit at different
  security levels. The account needs to clear the highest level any registered
  operation uses. That number should be discoverable rather than folklore —
  a validator that checks the configured account's rank against the registered
  operations' requirements would answer it permanently.
- **Should the live hand rate-limit itself?** Forty commands in a tight loop is
  forty round trips into a game server's main thread. Unclear whether that is a
  real problem or an imagined one; measure against a running world.

## Related

- `docs/architecture.md` — the live hand, and the selection limit
- `../wow-chat-2026/config/patches/C021-soap-loopback-console.sh` — where the
  endpoint gets turned on, and the security reasoning for loopback-only
- Issue 104 — the liveness probe this issue provides half of
