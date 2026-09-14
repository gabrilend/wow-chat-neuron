# 101a — One Deployment Shape

## Status
- Phase: 1 (Reach)
- Blocked by: 101 (the handle itself, which this changes the construction of)
- Blocks: pointing neuron at any AzerothCore that is not this one

## Current Behavior

**Built, and driven against both.** neuron reads the wow-chat deployment and a
stock AzerothCore clone at `/mnt/kaun/azeroth-core-blank/env/dist`, with no mode
switch between them.

    wow-chat                          stock
    profile     vanilla               profile     none
    port        3307                  port        3306
    user        ritz                  user        acore
    world db    acore_world_vanilla   world db    acore_world
    level cap   40                    level cap   80
    playerbots  acore_playerbots_...  playerbots  no such module
    SOAP        enabled               SOAP        disabled in the config

Every value on both sides is read from the server's own configuration and
carries the file and line it came from. Nothing is derived from a
directory-naming convention any more, and `secrets.conf` is not read at all.

`src/073-server-config.lua` does the reading. Its hardest property, and the one
under the most test, is that **the documentation is not the setting**: every
value appears twice in a stock config, once as an `Example` or `Default` in the
comment block above it and once for real, so a scan that is not anchored at the
start of the line reports the documented default as though it were configured
-- right often enough to be trusted, wrong exactly when somebody has changed
something.

Twenty-five tests on the reader, and the fixtures for the conversation loop and
the addon detection both changed: each used to build a wow-chat path itself, so
each only worked because that one deployment happened to be on this machine.

### What the config files already answer

The thing that makes this tractable, and the reason this is a small change
rather than a second implementation: **AzerothCore's own config files hold
almost everything neuron derives.**

    LoginDatabaseInfo     = "127.0.0.1;3307;ritz;menardi;acore_auth"
    WorldDatabaseInfo     = "127.0.0.1;3307;ritz;menardi;acore_world_vanilla"
    CharacterDatabaseInfo = "127.0.0.1;3307;ritz;menardi;acore_characters_vanilla"

Five fields per line, `host;port;user;pass;db`, in that format in every
AzerothCore that has ever been built. `authserver.conf` carries its own copy;
`playerbots.conf` carries `PlayerbotsDatabaseInfo`. Alongside them:

    SOAP.Enabled / SOAP.IP / SOAP.Port      the live hand's endpoint
    RealmServerPort / WorldServerPort       two of the three service ports
    MaxPlayerLevel                          the system prompt's level cap
    DataDir                                 where the maps are

So seven handle fields collapse into one parsed line, and the deployment's
`secrets.conf` stops being read: it is the wow-chat file that GENERATES those
lines, not an alternative to them, and the config is what the server itself
reads.

## Intended Behavior

**One shape, wide enough for both.** Not two layouts with a mode switch — a
mode is a thing that can be set wrongly, and every value it would imply is
either readable from a config file or settable by hand. The layout name
survives only as a *detection hint*: it decides where to look first and
nothing else.

Everything follows from **two paths**: where the deployment is, and where its
config files are.

### Detect, then override, and say which

Every derived value is computed from the two paths and the config files, and
every one of them can be replaced by a value in `config/deployment.lua`. An
override always wins — including when detection would later be right — because
a setting that quietly stops applying is worse than one that is wrong out
loud.

Each value carries where it came from, and the deployment section of the main
menu shows that:

    database port   3307        from worldserver.conf, line 121
    mysql client    /usr/bin/mysql          you set this
    config dir      .../installed-files-vanilla/etc     detected

The provenance is the whole point. "neuron worked this out" and "you told
neuron this" are different claims, and the standing position that a fallback
is a warning depends on being able to tell them apart at a glance.

### The configuration file

`config/deployment.lua` gains one table. Every key is optional; `nil` means
detect. One file, and its shape says which half is which.

    root      = "/path/to/the/deployment"
    overrides = {
        config_dir   = nil,   -- where the .conf files are
        profile      = nil,   -- absent on a stock install
        mysql_client = nil,   -- the binary neuron runs
        soap_account = nil,   -- neuron's own game account
        soap_key     = nil,
        api_key      = nil,
        servers      = nil,   -- see below
    }

### What no config file can answer

Six things, and this is the complete list:

| | why it cannot be read |
|---|---|
| the mysql client binary | neuron runs it; no server setting names it |
| how to start each server | not a server setting |
| the SOAP account name | it is neuron's account, not the server's |
| the SOAP password | a credential, and it lives in a key file |
| the profile | a wow-chat concept; a stock install has none |
| the Lua scripts directory | module-dependent, and ALE is optional |

Two are already settable. The rest become overrides.

### A service is three fields

The service list stops being source code. Each entry is:

| field | meaning |
|---|---|
| command | what to run |
| directory | where to run it from |
| config | a `--config` path, when the default lookup is wrong |

**A wrapper script and a bare binary are the same thing here**, and nothing
needs to know which it was handed. The wrapper resolves a profile, symlinks
logs into RAM and checks the database is up; neuron changes to the working
directory itself, which is the only one of those four that matters to a bare
binary, and a script that also does it is unharmed. The database check is
already in the menu, which will not enable start until mysql is up.

The working directory defaults to the directory holding the command, which is
right for a binary in `bin/` — AzerothCore looks for its config at `../etc`
relative to the binary, and a stock `DataDir = "."` is relative to the working
directory — and harmless for a script that changes directory itself.

**The log path is gone.** neuron captures the server's standard output into
its own file, and that output is a strict superset of the appender log: both
appenders hang off the same loggers, and stdout additionally carries what is
printed before logging is configured and what a crash writes on its way out.
The config's `LogsDir` is the server's business.

### The socket becomes a host and a port

`002-cold-hand.lua` builds a `mysql` command line with `--socket=`. The socket
path exists on the handle only because this deployment happens to keep one
locally; the config file gives a host and a port, which work for both a local
socket-less server and a remote one. `--host` and `--port` replace it, and a
handle field disappears rather than gaining an override.

### The database section is read-only

Everything about the connection is read out of the config file that the
worldserver itself reads. Making it editable in neuron would create a second
place to state it, and the two would disagree the first time somebody edited
one — which is the same failure the original issue avoided by refusing to
configure the profile twice.

It is DISPLAYED, with the file and line each value came from. The one
exception is the client binary, which is neuron's business and no server's.

### Where it lives

At the bottom of the main menu, after the sections that report state. It is
configuration somebody does once, and the lamps are what they came to look at.

## Suggested Implementation Steps

1. **Parse a `*DatabaseInfo` line.** `host;port;user;pass;db`, five fields, one
   function. Everything else depends on it, and it is the piece with the
   clearest right answer.
2. **Teach the cold hand a host and port.** Replace `--socket=` with `--host=`
   and `--port=`. Verify against the running deployment before anything else
   changes, since every read in the project goes through it.
3. **Find the config directory** from the root: the wow-chat pattern first,
   then the stock one, then an override. This is the detection hint and the
   only place layout knowledge lives.
4. **Rebuild the handle from the config files**, keeping every existing field
   name so nothing downstream changes. Values that were concatenated become
   values that were read, and each records its origin.
5. **Make the profile optional.** Absent, database names lose their suffix and
   the install directory is the config directory's parent. The concept does
   not vanish; there is one implicit profile.
6. **Turn the service list into data**, detected from the config directory and
   the binaries beside it, overridable per service.
7. **Add the deployment section** to the bottom of the main menu: the two
   paths, the profile, the service table, neuron's own account, and the
   read-only block of what was found.
8. **Move the level cap read onto the handle**, so the conversation loop asks
   for the config directory rather than rebuilding the path. One line, and it
   is the difference between a generalization that is done and one that looks
   done.
9. **Gate the log button** on having something to read: the captured output for
   a server neuron started, the appender log where the config names one, and
   disabled otherwise.
10. **Point neuron at the blank install** at `/mnt/kaun/azeroth-core-blank` and
   drive it, which is the only test that proves the shape is wide enough.

## Related

- `issues/101-deployment-handle-and-configuration.md` — the handle this
  changes the construction of, and the reasoning behind deriving rather than
  configuring, which this narrows rather than reverses
- `src/000-deployment.lua` — where the twenty derived values are built
- `src/058-services.lua` — the hardcoded service list
- `src/002-cold-hand.lua` — the socket the config file replaces
- `src/072-addons.lua` — already reads the config directory, and is the model
  for reading rather than assuming
- `src/059-menu.lua` — the profile and deployment routes, and the page

## Settled

**The log button is greyed out when there is nothing to show.** neuron captures
standard output for a server it launched, and that file does not exist for one
started in a terminal. Where the appender log can be located -- `LogsDir` and
the appender's filename are both in the config -- read that instead. Where it
cannot, the button is disabled rather than showing a stale capture from an
earlier run with nothing admitting it.

**Two config files disagreeing is refused, naming both lines.** `authserver.conf`
and `worldserver.conf` each carry a `LoginDatabaseInfo` and nothing keeps them
in step. Picking one would mean neuron and one of the two servers reach
different databases while everything looks fine. The error names both files,
both line numbers and both values.

**A profile-less deployment still shows the profile control, greyed.** Hiding it
makes the two kinds of deployment look like different programs. One greyed entry
says the concept exists and does not apply here, which is the true thing.

**`secrets.conf` is not read.** It is a wow-chat file -- AzerothCore has never
heard of it -- and it is the SOURCE that `scripts/generate-configs` copies into
the `.conf` files, not an alternative to them. The password lands in
`worldserver.conf` in plaintext either way, so reading `secrets.conf` hides
nothing. It can only differ from the generated config when somebody edited it
and did not regenerate, and in that case the SERVER is using the generated one
too -- so reading the config keeps neuron in step with the thing it is driving,
and reading `secrets.conf` would make neuron the only participant using a
password nothing else knows.

**The level cap is read through the handle.** The conversation loop needs the
world's maximum character level for the system prompt, and finds it by building
`<root>/installed-files-<profile>/etc/worldserver.conf` itself and scanning for
`MaxPlayerLevel`. That is the wow-chat layout convention written out a second
time, in a file that has nothing to do with deployment layout. Left alone, the
deployment section would locate a stock install's config correctly while the
conversation loop kept looking in the wow-chat place and reported the cap as
unreadable. Anything wanting a config file asks the handle for the directory.

## Open Questions

None outstanding. The five that shaped this issue are recorded above.
