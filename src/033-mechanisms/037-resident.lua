--------------------------------------------------------------------------------
-- 037-resident.lua
--
-- The resident hand as a mechanism: install a Lua script into the running
-- worldserver, where it stays and keeps running on the server's tick.
--
-- The only hand whose effect OUTLIVES THE CALL. Cold and live both do one thing
-- and come back; this one leaves something behind that keeps deciding. That is
-- what a guard holding a hill is, and what a creature that keeps narrating its
-- afternoon is, and neither is expressible any other way.
--
-- It is also the only one of the four that is new here rather than a doorway
-- onto an existing file. 000-deployment.lua has always computed where such a
-- script would go -- the profile's ALE custom script directory -- and until now
-- nothing wrote to it.
--------------------------------------------------------------------------------

local here = debug.getinfo(1, "S").source:match("^@(.*/)")
local Load = dofile(here .. "../024-load.lua")

local Mechanism = Load(here .. "034-mechanism.lua")
local Hands     = Mechanism.Hands
local Refusals  = Mechanism.Refusals

-- {{{ RELOAD_COMMAND
-- ============================================================================
-- UNVERIFIED AGAINST THIS DEPLOYMENT'S ALE.
--
-- ALE is a fork of Eluna, whose reload is `.reload eluna`. That is what this
-- sends. It has NOT been run against the worldserver in this project, because
-- no worldserver has been up during any session that touched this file.
--
-- To verify: start the worldserver, then
--     scripts/neuron ... (any resident step)
-- and read the console text this returns. A command the server does not know
-- comes back as a sentence saying so, in the body of an HTTP 200 -- which
-- 003-live-hand.lua already turns into a failure rather than a success, so a
-- wrong command here surfaces as a refusal with the server's own words in it
-- rather than as a script that silently never loaded.
--
-- The prefix `reload` is what LiveHand.COMMANDS matches on for addressing, and
-- it is addressed `none`, so the subcommand can change without the addressing
-- table changing.
-- ============================================================================
local RELOAD_COMMAND = "reload eluna"
-- }}}

-- {{{ shell_quote(text)
local function shell_quote(text)
    return "'" .. tostring(text):gsub("'", "'\\''") .. "'"
end
-- }}}

return Mechanism.define {
    hand = Hands.resident,

    -- {{{ probe
    -- Borrows the live probe, because ALE lives inside the worldserver and a
    -- worldserver that is not answering cannot host a script.
    --
    -- KNOWN GAP: a worldserver running with ALE disabled is up, answers the
    -- probe, and cannot host a resident script at all. Nothing here
    -- distinguishes those two states, so the failure arrives later as a script
    -- that installed fine and never ran. See issue 700's open questions.
    probe = function(handle)
        local LiveHand = Load(handle.neuron_root .. "/src/003-live-hand.lua")
        local up, reason, detail = LiveHand.probe(handle)
        return up, reason, detail
    end,
    -- }}}

    -- {{{ describes
    describes = function(step)
        return step.describes
            or ("install " .. tostring(step.script_name) .. " into the world")
    end,
    -- }}}

    -- {{{ perform
    -- Three acts, in order, each verified before the next: write the file, read
    -- it back, ask the server to reload.
    --
    -- The read-back matters more than it looks. A script that fails to write --
    -- a full disk, a directory that is not there because the profile was never
    -- installed -- produces exactly the same outcome as one that wrote fine and
    -- never ran, if nobody checks. They have completely different fixes.
    perform = function(handle, step)
        local name = tostring(step.script_name)

        -- The filename IS the installed thing's identity: removing it later
        -- means knowing what it was called. A name that could escape the
        -- directory would let a step write anywhere the worldserver's user can,
        -- so the shape is fixed rather than sanitised -- sanitising invites the
        -- question of what was stripped, and refusing does not.
        if not name:match("^[%w][%w%-_]*$") then
            return Mechanism.failed(Refusals.argument, string.format(
                "'%s' is not a usable resident script name.\n"
             .. "  A name may hold letters, digits, dashes and underscores, and\n"
             .. "  must start with a letter or digit. No dots, no slashes.\n"
             .. "  The name is the installed script's identity -- it is how the\n"
             .. "  script is found again in order to be replaced or removed --\n"
             .. "  and a name that could contain a path separator would let a\n"
             .. "  step write outside the script directory entirely.", name))
        end

        local path = handle.lua_custom_dir .. "/" .. name .. ".lua"

        local file, why = io.open(path, "w")
        if not file then
            return Mechanism.failed(Refusals.unavailable, string.format(
                "cannot write the resident script to %s\n"
             .. "  %s\n"
             .. "  Wrote: nothing. Reloaded: nothing.\n"
             .. "  To debug: does that directory exist? It is the profile's ALE\n"
             .. "  custom script directory, created when the profile is\n"
             .. "  installed -- if the profile has never been installed the\n"
             .. "  directory is absent, which is a deployment problem rather\n"
             .. "  than a neuron one. If it exists, this is a permissions\n"
             .. "  problem: the worldserver's files belong to whoever installed\n"
             .. "  it, which may not be whoever is running neuron.",
                path, tostring(why)))
        end

        file:write(step.script)
        file:close()

        -- Read back. Proves the bytes landed, and catches a write that was
        -- accepted and truncated.
        local written = io.open(path, "r")
        if not written then
            return Mechanism.failed(Refusals.unavailable, string.format(
                "wrote %s and then could not read it back.\n"
             .. "  Wrote: apparently. Reloaded: nothing.\n"
             .. "  A file that vanishes between writing and reading is either a\n"
             .. "  filesystem being cleared underneath us or a path that is not\n"
             .. "  what it appears to be -- check whether lua_custom_dir is a\n"
             .. "  symlink into a tree that was replaced.", path))
        end

        local contents = written:read("*a")
        written:close()

        if #contents ~= #step.script then
            return Mechanism.failed(Refusals.unavailable, string.format(
                "%s is %d bytes and the script was %d.\n"
             .. "  Wrote: partially. Reloaded: nothing.\n"
             .. "  A short write is usually a full filesystem. The script\n"
             .. "  directory may be on the RAM tier, which is small.",
                path, #contents, #step.script))
        end

        -- Ask the world to pick it up. Until this succeeds the script is a file
        -- on disk that nothing is running.
        local LiveHand = Load(handle.neuron_root .. "/src/003-live-hand.lua")
        local output, reload_why = LiveHand.execute(handle, RELOAD_COMMAND)

        if not output then
            return Mechanism.failed(Refusals.refused, string.format(
                "installed %s but the world would not reload.\n"
             .. "  %s\n"
             .. "  Wrote: yes, %d bytes, verified by reading it back.\n"
             .. "  Reloaded: no. The script is on disk and is not running.\n"
             .. "  Sent: .%s\n"
             .. "  To debug: is that the right reload command for this ALE? It\n"
             .. "  is unverified -- see the comment at the top of this file. A\n"
             .. "  command the server does not know comes back as a sentence\n"
             .. "  saying so, which is what the line above holds.\n"
             .. "  The script will load on the worldserver's next start\n"
             .. "  regardless, so this is a timing failure rather than a lost\n"
             .. "  change.", path, tostring(reload_why), #contents, RELOAD_COMMAND))
        end

        -- Whether the script COMPILED is a separate question this cannot see. A
        -- script with a syntax error installs fine and simply never runs, which
        -- looks exactly like the feature not working. The console's own words
        -- are returned so a reader can see what it said about the reload.
        return Mechanism.done(1, string.format(
            "%s installed (%d bytes) and the world reloaded: %s",
            name, #contents, (output:gsub("%s+$", ""))))
    end,
    -- }}}
}
