# 112 — neuron's Own Databases

## Status
- Phase: 1 (Reach)
- Blocked by: 101 (deployment handle)
- Done, provisioned against the live installation

## Current Behavior

neuron acted on `acore_*_vanilla` — the same databases the deployment's vanilla
profile uses. Every operation was therefore one mistake away from changing a
world somebody else was using, and the character removal in issue 404 was that
mistake made deliberately.

## Intended Behavior

neuron owns `acore_world_neuron`, `acore_characters_neuron`, and
`acore_playerbots_neuron`, and never opens vanilla, alpha, beta, or release for
writing.

### A second database inside the same database

The question that settled the design: are the profiles separate database
*servers*, or separate *databases* inside one server?

They are the second. One `mysqld`, eleven schemas, one set per profile,
distinguished by a name suffix. So a new profile is three `CREATE DATABASE`
statements, not an installation.

A separate MySQL instance on its own disk was considered and declined. It gives
true process-level isolation and a roomier disk, at the cost of a second thing to
start, stop, back up, and keep in step. The profile system already exists to
solve exactly this, and using it as intended beats building beside it.

The isolation is therefore **by convention, enforced by naming**: nothing stops
a badly-written operation from naming a vanilla table, and what prevents it is
that every database name in the project is derived from one profile string in
one function.

### The profile is now chosen, not only read

Issue 101 established that the profile is read from the deployment's own
`.profile` rather than configured, because two copies of that answer can
disagree and the failure is silent writes to the wrong database.

That reasoning still holds, and it is now the **default** rather than the only
option. `config/deployment.lua` may name a profile explicitly, which is a
different act from duplicating the deployment's answer: it says "I know what the
deployment is running, and I mean a different one." That is exactly this
situation — neuron owns databases alongside the four the deployment switches
between, and acts on them whichever one the deployment has selected.

Because an override is easy to forget, it is **reported** everywhere the
deployment is described, rather than being quietly in effect. A silent override
would mean reading one world while believing you are reading another: the same
class of mistake the original rule prevents, arrived at from the other side.

### What was copied, and what was not

| Database | Source | Contents |
|----------|--------|----------|
| `acore_world_neuron` | `acore_world_vanilla` | Full copy — 149,923 creature spawns, 313 tables, 422 MB |
| `acore_characters_neuron` | `acore_characters_vanilla` | **Structure only.** 112 tables, no characters. |
| `acore_playerbots_neuron` | `acore_playerbots_vanilla` | Structure only. |

Accounts were deliberately not copied. `acore_auth` carries no profile suffix
and is shared by every profile on the machine, which is how the game itself
expects several realms to work.

### Two privileges, and why the split is kept

The deployment's everyday database user holds ALL PRIVILEGES on each existing
game database, granted one at a time, and only USAGE globally — so it cannot
create a database. That is a sensible arrangement and not something to work
around permanently.

So creation is done once as the administrator, the everyday user is granted
rights on the new databases, and everything afterwards runs as the everyday user
exactly as it does against the existing profiles.

**The administrator account on this installation has no password.** The database
was initialised with `--initialize-insecure`, and the install script's own final
instruction — set a root password — was never carried out. It is reachable only
through a unix socket inside the deployment directory and never over the
network, so the exposure is to local users of this machine rather than to
anything remote. It should be fixed, and fixing it belongs to the deployment.

## Suggested Implementation Steps

1. Write `scripts/provision-profile`: create the three databases, copy a source
   world in full, copy characters and playerbots as structure only, and grant
   the everyday user rights on all three.
2. Refuse when source and target are the same suffix. The whole point is not
   writing to another profile's data, and a wrong flag should not be able to
   defeat that.
3. Give it a `--drop` so the profile can be removed as easily as it is made.
4. Add the profile override to the config and the handle, and make every
   description say when it is in effect.
5. Verify afterwards that the other profiles' row counts are unchanged.

## Open Questions

- **Should neuron have its own database user?** One granted rights on the
  `_neuron` databases only would make the isolation structural instead of
  conventional — a mis-aimed operation would be refused by the server rather
  than merely unlikely. This is the obvious next step and is not done.
- **Is a copied vanilla world the right base?** See issue 111. It carries the
  vanilla ruleset in its data, and a plain WotLK world means removing that.
- **What happens when the deployment switches profiles?** Nothing, now. The
  override means neuron acts on its own databases regardless. Whether it should
  ever follow the deployment instead is undecided.

## Related

- Issue 101 — where "read the profile, do not configure it" was established
- Issue 111 — the plain WotLK target, and what this world copy still carries
- Issue 404 — the removal that made the shared-database risk concrete
