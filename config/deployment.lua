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
    profile = "neuron",

    -- How long to wait on each service before calling it down, in seconds.
    -- Short, because these probes run before real work and a hung probe is
    -- indistinguishable to the user from a hung tool.
    probe_timeout_seconds = 3,
}
