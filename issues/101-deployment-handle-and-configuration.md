# 101 — Deployment Handle and Configuration

## Status
- Phase: 1 (Reach)
- Blocks: every other issue in the project
- Blocked by: nothing

## Current Behavior

**Built.** `src/000-deployment.lua` returns the handle, cached per process, and
every operation in the project takes it as its first argument. The failure
modes described below are all in place: a missing config file, an unreadable
`.profile` and absent credentials each name the file and stop.

The handle has grown from the twelve fields listed below to twenty-four. Four
are configured; the rest are built by string concatenation from those four.

That concatenation is what issue 101a changes. Every derived value encodes a
convention belonging to this deployment rather than to AzerothCore, so neuron
refuses a stock install — correctly, since it cannot find what it needs, and
uselessly, since almost all of it is sitting in the server's own config files.
The position below on deriving rather than configuring survives that change; it
is narrowed to "read it from the file the server reads" rather than reversed.

## Intended Behavior

A single function returns a **deployment handle**: one table holding every
concrete fact needed to reach a running Everland Ghostsong installation. Every
operation in the project receives this table as its first argument and reads
its paths, database names, and credentials from it. No operation ever builds a
path or a database name itself.

The handle is built once per process and cached, because building it reads
three files off disk and probes two services, and doing that per operation
would make a forty-step plan do two hundred pointless reads.

### What the handle holds

| Field | Type | Where it comes from |
|-------|------|---------------------|
| `root` | string | `config/deployment.lua`, absolute path |
| `profile` | string | the deployment's own `.profile` file |
| `mysql_socket` | string | `<root>/mysql/databases/mysql.sock` |
| `mysql_user` | string | the deployment's `secrets.conf` |
| `mysql_password` | string | the deployment's `secrets.conf` |
| `db_world` | string | derived: `acore_world_<profile>` |
| `db_characters` | string | derived: `acore_characters_<profile>` |
| `db_playerbots` | string | derived: `acore_playerbots_<profile>` |
| `soap_url` | string | `config/deployment.lua` |
| `soap_account` | string | `config/deployment.lua` |
| `soap_password` | string | neuron's own `secrets.conf` |
| `lua_custom_dir` | string | derived from root, profile, and install layout |

### Two things deliberately not configured

**The profile is read, not set.** The deployment already records which profile
is active, in `.profile` at its root. Configuring it a second time in neuron
creates a way for the two to disagree, and when they disagree neuron writes to
the wrong database and everything looks fine until it doesn't.

**Database names are derived, not listed.** The deployment derives them from
the profile by the same rule. If that convention ever changes, one function
changes with it. Three configured strings would each have to be found.

### Failure is loud

A missing config file, an unreadable `.profile`, or absent credentials is an
error that names the file and stops. There is no default deployment, no
fallback to a guessed path, and no "assume vanilla". Per the standing project
position, a fallback here would be a warning, and a warning is an error.

## Suggested Implementation Steps

1. Write `config/deployment.lua` as a returned Lua table — deployment root,
   SOAP URL, SOAP account name. Ship a `.example` alongside it and gitignore
   the real one, matching how the sibling project handles `secrets.conf`.
2. Write the config loader in the `000` foundation band of `src/`. It reads the
   config table, then the deployment's `.profile`, then both `secrets.conf`
   files.
3. Write the credential reader. The deployment's `secrets.conf` is a shell
   fragment of `KEY=value` lines; parse it as such rather than sourcing it,
   because sourcing an arbitrary file is exactly the kind of reach this project
   exists to avoid.
4. Write the derivation function mapping profile name to the three database
   names. One function, one place.
5. Write the handle constructor that assembles all of the above, caches the
   result in a file-local upvalue, and returns it.
6. Write the accompanying `.info.md` describing the handle's fields down to
   their primitive types, so a reader never has to open the source to know what
   is in it.

## Open Questions

- **Should neuron support more than one deployment at a time?** The handle is
  cached as a single value, which assumes one. Supporting several would mean
  keying the cache and passing a deployment name through the CLI. Not needed
  yet; the shape does not preclude it.
- **Whose `secrets.conf` holds the SOAP password?** Currently neuron's own, on
  the reasoning that the GM account is neuron's identity rather than the
  deployment's. See open question 2 in `docs/architecture.md`.

## Related

- `docs/architecture.md` — the deployment handle table and the liveness matrix
- `docs/datapath-operation-dispatch.md` — step 3, Resolve
- Sibling project's `scripts/mysql-client` and `scripts/credentials` — the
  established shape for socket connection and credential storage
