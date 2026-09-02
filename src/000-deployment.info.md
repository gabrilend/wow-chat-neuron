# 000-deployment.lua

Resolves "which world" into one table of concrete facts. Every operation takes
that table as its first argument, so no operation builds a path or a database
name itself.

Built once and cached for the process.

## Functions

### `Deployment.load() -> handle`
No arguments. Returns the deployment handle. Errors — loudly, naming the file —
if the config is missing, the deployment has no `.profile`, or the config names
no root. There is no default deployment and nothing is guessed.

### `Deployment.forget()`
Drops the cache. For tests that need to load, change something on disk, and
load again.

### `Deployment.describe(handle) -> string`
A multi-line human summary of what the handle points at. Used by the status
board and by error reports — naming the world in an error is how you notice you
are pointed at the wrong one.

## The handle

| Field | Type | Meaning |
|-------|------|---------|
| `neuron_root` | string | Absolute path to this project |
| `root` | string | Absolute path to the deployment |
| `profile` | string | Active profile, read from the deployment's `.profile` |
| `mysql_binary` | string | The deployment's own mysql client |
| `mysql_socket` | string | Its unix socket |
| `mysql_user` | string | Database user |
| `mysql_password` | string or nil | From the deployment's `secrets.conf` |
| `db_world` | string | `acore_world_<profile>` |
| `db_characters` | string | `acore_characters_<profile>` |
| `db_playerbots` | string | `acore_playerbots_<profile>` |
| `soap_url` | string | The worldserver's SOAP endpoint |
| `soap_account` | string | A game account holding GM rank |
| `soap_password` | string or nil | From neuron's own `secrets.conf` |
| `lua_custom_dir` | string | Where ALE loads custom scripts from |
| `probe_timeout` | number | Seconds before a service is called down |
| `receipts_dir` | string | Under the RAM-backed shared-memory tier |

Two things are deliberately derived rather than configured: the profile is read
from the deployment, and the three database names are computed from it. A second
copy of either would be a second thing to keep in sync, and the failure mode of
disagreement is silent writes to the wrong database.
