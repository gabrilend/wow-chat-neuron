# 801 — Talking to the API

## Status
- Phase: 8 (The Voice)
- Blocked by: nothing
- Blocks: 802 (the conversation loop), and through it the whole asking half

## Current Behavior

**Built.** `src/050-api.lua`, with `config/asking.lua` for the endpoint, model,
timeouts and turn cap, and `NEURON_API_KEY` added to `secrets.conf.example`.

`curl` carries it, for the reason below. No live request has been made: no key
is configured in this checkout. What is exercised is every refusal — the two
absences (no config, no key) come back as different answers with different
fixes, and the nine failure kinds are distinguishable by name.

The key never reaches a command line. It is written to a header file on the RAM
tier with `chmod 600`, handed to `curl` by path, and deleted — because anything
in an argument list is visible in `ps` to every user on the machine. Request and
response bodies go the same way, since a tool list plus a conversation is far
past any safe argument length.
## Intended Behavior

Send a JSON body to an HTTPS endpoint and get one back.

### `curl`, not a library

The project already reaches outside itself twice, and both times by running a
program: `002-cold-hand.lua` runs the deployment's own `mysql` binary, and
`003-live-hand.lua` speaks HTTP to the SOAP console. Running `curl` is the same
shape of thing, and it brings TLS, redirects, timeouts and proxy handling that
would otherwise have to be written.

The alternative is linking a TLS library, which means a build step, a
dependency, and a version of this project that does not run on a machine where
it currently does.

### The key does not go on the command line

Anything on a command line is visible in `ps` to every user on the machine. The
key goes in a header file `curl` reads, or on its standard input — never as an
argument, and never into a receipt or a log line.

It belongs in `secrets.conf` beside the database password, which is already
untracked and already read by the deployment handle.

### Failures have to be distinguishable

A caller needs to tell these apart, because the right response differs:

| | Means | Do |
|---|---|---|
| no key configured | nobody set it up | say so, plainly, once |
| curl missing | the machine lacks it | say which program |
| connection failed | network, or the endpoint is down | retry later |
| 401 | the key is wrong or revoked | stop; retrying will not help |
| 429 | rate limited | wait, and the response says how long |
| 529 / 5xx | the service is overloaded | retry with a delay |
| 200 with an `error` object | the request was malformed | fix the request; this is our bug |

The last row is the one that gets missed. A body that parses as JSON and carries
an error is not a success, and a caller checking only the exit status will
believe it worked — which is exactly the failure `003-live-hand.lua` already
documents for the SOAP console, where a rejected command returns HTTP 200 with a
sentence in the body.

### Bodies go through files, not arguments

A tool list plus a conversation is far past any safe command-line length. The
request body is written to the RAM tier and handed to `curl` as `--data-binary
@path`; the response comes back the same way. Both are deleted after, because a
conversation on disk is a conversation somebody can read.

## Suggested Implementation Steps

1. Read the key from `secrets.conf` through the deployment handle. Refuse
   plainly and early when it is absent; do not send a request without one to
   find out.
2. Write the body to the RAM tier, call `curl`, read the response back, delete
   both.
3. Capture the status code separately from the body — `--write-out` puts it
   somewhere the body is not.
4. Decode with `001-json.lua`, which already exists.
5. Return failures as values in the four-kind vocabulary the rest of the project
   uses, so the loop above can turn any of them into something a person reads.
6. Test the failure paths deliberately: no key, wrong key, malformed body.
   Those are the paths that will actually run.

## Open Questions

- **Which model, and where is that written?** A model name is a configuration
  value that changes more often than code and belongs beside the deployment
  handle rather than in a constant.
- **Is streaming needed?** A tool-calling turn is not read as it arrives, so
  probably not for the loop. A creature narrating an afternoon is read as it
  arrives, so probably yes for phase 10.
- **What is the timeout?** Long enough for a real answer and short enough that a
  hung request does not hold a chat window open forever, and those two numbers
  are not obviously compatible.
- **Where do requests get recorded?** A receipt says what was done to the world.
  What was *asked* is a different log, and having it is the difference between
  debugging a bad plan and guessing at one.

## Related

- Issue 802 — the loop this carries
- Issue 703 — the tool list that goes in the body
