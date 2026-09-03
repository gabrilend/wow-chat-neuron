# 022-http-server.lua

A small HTTP server so the chat window has something to talk to. Three routes,
no framework, built on luasocket which is already present.

## Functions

### `HttpServer.new(handle, options) -> server`
`options.port` defaults to 7879 — next to the deployment's game-master console
on 7878, deliberately.

### `HttpServer.run(server) -> nil, why`
Listens until interrupted. Returns only on failure to bind.

## Routes

| Route | Does |
|---|---|
| `GET /` | The chat window, re-read from disk each request so edits show on refresh |
| `POST /ask` | A sentence in; an answer out |
| `POST /apply` | Run a held plan by id |

## Answer shapes

| `kind` | Means |
|---|---|
| `said` | Plain output; nothing changed. May carry `people` for class-coloured rosters |
| `plan` | Something *would* change; carries `plan_id` to confirm |
| `done` | A plan ran |
| `trouble` | It could not be done, and why |

## Plans are held, not recomputed

A plan is kept server-side keyed by id, and confirming runs **exactly what was
shown** rather than planning again — a fresh computation could differ.

It is **removed as it runs**, whatever the outcome. A plan is a statement about
the world at one moment; leaving it runnable twice is how somebody teleports a
party to the docks twice and wonders why the second did nothing.

Plans live in memory and die with the process, which is correct: one that
outlived the server would describe a world that may have moved on.

## Loopback only

Bound to `127.0.0.1` and nothing else, for the same reason the deployment binds
its game-master console there: this can empty a world and it authenticates
nobody.

## Two things learned by running it

**Query strings are split from the path.** The request target carries the query
with it, so `/` and `/?ask=hello` arrive as different strings — comparing the
whole target against a route made every parameterised link a 404.

**Operations run under `pcall`.** A fault in one operation returns an error to
the page instead of killing the server the page is talking to.
