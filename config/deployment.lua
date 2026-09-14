--------------------------------------------------------------------------------
-- config/deployment.lua
--
-- Which running world this copy of neuron reaches into.
--
-- neuron does not build, patch, or install a game server. It attaches to one
-- that already exists and changes the state of it. This file is the only place
-- that says which one.
--
-- Two things are deliberately absent and must stay absent:
--
--   * The profile name. The deployment already records which profile is active
--     in its own `.profile` file. Recording it here too creates a way for the
--     two to disagree, and when they disagree neuron writes to the wrong
--     database and everything looks fine until it very much does not.
--
--   * Database names. They are derived from the profile by the same rule the
--     deployment itself uses. One derivation, one place to change it.
--
-- Passwords are not here either. They live in `secrets.conf`, which is not
-- tracked.
--------------------------------------------------------------------------------

return {
    -- Absolute path to the deployment project directory. This is the directory
    -- holding `.profile`, `mysql/`, `installed-files-<profile>/`, and so on.
    root = "/mnt/mtwo/games/azeroth-core/wow-chat-2026",

    -- The worldserver's SOAP console. The deployment binds this to loopback
    -- and nothing else; see its config/patches/C021-soap-loopback-console.sh
    -- for the reasoning. If that address is ever not loopback, something is
    -- wrong with the deployment, not with this file.
    soap_url = "http://127.0.0.1:7878/",

    -- A game account that holds GM rank. Its commands are the live hand.
    -- The password for it lives in secrets.conf under NEURON_SOAP_PASSWORD.
    soap_account = "neuron",

    -- WHERE THE KEYS ARE. Paths, never values.
    --
    -- A credential is a file this points at. It is read at the moment it is
    -- used and let go again -- it is never parsed into this table, never
    -- carried in the handle, and never put in an environment variable, because
    -- a secret that travels through a config is a secret every function
    -- receives whether it wanted it or not.
    --
    -- Each file holds the credential ALONE. No name, no equals sign, no
    -- comment. Mode 600, in a directory with mode 700.
    --
    --     mkdir -p secrets && chmod 700 secrets
    --     printf '%s' 'the-password' > secrets/soap.key
    --     chmod 600 secrets/soap.key
    soap_key = "secrets/soap.key",
    api_key  = "secrets/api.key",

    -- Which profile to act on.
    --
    -- Leave this nil and neuron reads the deployment's own `.profile` file,
    -- which is the right default: the deployment is the authority on what it is
    -- running, and a second copy of that answer is a second thing to keep in
    -- step.
    --
    -- Setting it is NOT the same as duplicating that answer. It says "I know
    -- what the deployment is running, and I mean a different one" -- which is
    -- exactly the situation here, because neuron owns its own set of databases
    -- alongside the four the deployment switches between, and acts on them
    -- whichever profile the deployment happens to have selected.
    --
    -- Because an override is easy to forget, it is REPORTED everywhere the
    -- deployment is described, rather than being quietly in effect.
    --
    -- NOW NIL, deliberately. The override pointed at `neuron`, a sandbox set of
    -- databases holding zero characters, while the deployment was running
    -- `vanilla` with twenty-five thousand. Everything neuron said about the
    -- world was true of the sandbox and useless about the world -- and it read
    -- as an empty server rather than as the wrong one, because an empty database
    -- and an empty world are the same answer.
    --
    -- Set it again only to mean "I know what is running and I want a different
    -- one", and expect the status board to keep saying so.
    profile = nil,

    -- How long to wait on each service before calling it down, in seconds.
    -- Short, because these probes run before real work and a hung probe is
    -- indistinguishable to the user from a hung tool.
    probe_timeout_seconds = 3,

    -- {{{ overrides
    -- Every value neuron works out for itself, and how to say otherwise.
    --
    -- nil means DETECT. A value here means you said so, and an override always
    -- wins -- including over a detection that would later be right, because a
    -- setting that quietly stops applying is worse than one that is wrong out
    -- loud. The deployment section of the main menu says which each row is.
    --
    -- Almost everything about a deployment is in the server's own config files
    -- and is read from there rather than listed here. What is left is the six
    -- things no config file can answer, because they are neuron's business
    -- rather than the server's.
    overrides = {
        -- Where the .conf files are. Detected as installed-files-<profile>/etc,
        -- then env/dist/etc, then etc/. Setting this skips detection entirely
        -- and is how a deployment shaped like neither is reached.
        config_dir   = nil,

        -- Each config file, when they are not both in that directory. Named
        -- outright rather than found, which is how a deployment that keeps
        -- them apart is reached.
        worldserver_conf = nil,
        authserver_conf  = nil,

        -- Which profile. Read from the deployment's own .profile; a deployment
        -- with no such file has one implicit profile and no suffix on its
        -- database names.
        profile      = nil,

        -- The mysql client binary neuron runs. It runs one rather than linking
        -- a driver, and no server setting names it.
        mysql_client = nil,

        -- neuron's own game account, and where its password lives. The account
        -- belongs to neuron rather than to the server, so nothing in the
        -- server's configuration knows about it.
        soap_account = nil,
        soap_key     = nil,
        api_key      = nil,

        -- Where ALE looks for scripts. Only meaningful with the module
        -- installed, and profile-shaped.
        lua_custom_dir = nil,

        -- The SOAP endpoint, when the server answers somewhere other than
        -- where it believes it listens -- through a tunnel, or a container.
        soap_url     = nil,
    },
    -- }}}

    -- {{{ services
    -- How to start each server, when the detected command is wrong.
    --
    -- Three fields, and a wrapper script and a bare binary are the same thing:
    --
    --     command    what to run
    --     directory  where to run it from; defaults to the command's own
    --                directory, which is what a binary in bin/ needs
    --
    -- A stock install would say something like
    --
    --     worldserver = {
    --         command = "/path/env/dist/bin/worldserver",
    --     },
    --
    -- and the working directory follows from the command.
    --     environment  variables to export before it runs
    --
    -- The environment is the one that is easy to miss. This deployment's
    -- worldserver wrapper exports LD_LIBRARY_PATH pointing at its own mysql
    -- lib directory, because the server links against a client library that is
    -- not the system's. A wrapper does that for itself; a bare binary has to be
    -- told, and there is nowhere else to say it:
    --
    --     worldserver = {
    --         command     = "/path/env/dist/bin/worldserver",
    --         environment = {
    --             LD_LIBRARY_PATH = "/path/mysql/installed-files/lib",
    --         },
    --     },
    services = {
        mysql       = nil,
        authserver  = nil,
        worldserver = nil,
    },
    -- }}}
}
