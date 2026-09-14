--------------------------------------------------------------------------------
-- 072-addons.test.lua
--
-- Which words are unavailable because a module was not built in.
--
-- The failure this prevents is a tool that is offered and cannot work. A model
-- given one tries it, gets a failure it cannot interpret, and tries again; a
-- person reading the library cannot tell "no such word" from "that word needs
-- something this server was built without". Two different answers, and only
-- one of them is actionable.
--------------------------------------------------------------------------------

local ROOT   = "/mnt/mtwo/games/azeroth-core/wow-chat-neuron"
local Addons = dofile(ROOT .. "/src/072-addons.lua")

local passed, failed = 0, 0

-- {{{ check(what, got, want)
local function check(what, got, want)
    if got == want then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL  " .. what)
        print("        got  " .. tostring(got))
        print("        want " .. tostring(want))
    end
end
-- }}}

local WORK = "/tmp/claude-1000/-mnt-mtwo-games-azeroth-core-wow-chat-neuron/"
          .. "bedafefb-6053-4b5b-b904-cb058c036837/scratchpad/addons-test"
os.execute("rm -rf '" .. WORK .. "'")
os.execute("mkdir -p '" .. WORK .. "/installed-files-vanilla/etc/modules'")

-- The config directory is CARRIED, not rebuilt from a root and a profile.
--
-- Detection used to glue `installed-files-<profile>/etc/modules` together
-- itself, which meant it quietly answered "nothing installed" on every
-- deployment that does not use profiles -- and reported every module-dependent
-- word as disabled on a server that had them.
local HANDLE = {
    root       = WORK,
    profile    = "vanilla",
    config_dir = WORK .. "/installed-files-vanilla/etc",
}

-- {{{ nothing installed
local present, listed = Addons.installed(HANDLE)

check("mod-ale is not there",             present.ale,                    false)
check("nor playerbots",                   present.playerbots,             false)
check("both are still listed",            #listed,                            2)
check("each says why it is missing",
    listed[1].why ~= nil and listed[2].why ~= nil,                         true)
-- }}}

-- {{{ a word that needs one is unavailable, and says which
local why = Addons.why_missing(HANDLE, { "ale" })
check("a word needing ale is unavailable",       why ~= nil,             true)
check("and the reason names the module",
    why:find("mod-ale", 1, true) ~= nil,                                  true)

-- Both, when it needs both -- installing one of them would not help, so saying
-- only one would send somebody to do half a job.
local both = Addons.why_missing(HANDLE, { "ale", "playerbots" })
check("needing two names two",
    both:find("mod%-ale") ~= nil and both:find("mod%-playerbots") ~= nil,  true)

check("a word needing nothing is available",
    Addons.why_missing(HANDLE, {}),                                        nil)
check("and so is one with no needs at all",
    Addons.why_missing(HANDLE, nil),                                       nil)
-- }}}

-- {{{ installing one changes the answer
-- Detected from the config the module's own install step writes, in the
-- PROFILE's installed tree -- so switching profiles can change this, which is
-- why nothing here is cached.
local file = io.open(WORK .. "/installed-files-vanilla/etc/modules/mod_ale.conf", "w")
file:write("Ale.Enable = 1\n")
file:close()

check("ale is now there",     (Addons.installed(HANDLE)).ale,             true)
check("and the word needing it is available",
    Addons.why_missing(HANDLE, { "ale" }),                                 nil)
check("while the other is still missing",
    Addons.why_missing(HANDLE, { "playerbots" }) ~= nil,                  true)
-- }}}

-- {{{ another config directory is a different answer
-- Whether by profile or by deployment, pointing somewhere else must give a
-- different answer -- so nothing here may be cached. A deployment can have one
-- profile built with playerbots and one without, and an answer worked out at
-- startup would describe whichever was active then.
check("another config directory has its own modules",
    Addons.installed({ root = WORK,
                       config_dir = WORK .. "/installed-files-beta/etc" }).ale,
                                                                         false)

-- And a deployment with no profiles at all, which is most AzerothCore
-- installs. It has a config directory like any other.
os.execute("mkdir -p '" .. WORK .. "/env/dist/etc/modules'")
check("a profile-less deployment is read the same way",
    Addons.installed({ root = WORK,
                       config_dir = WORK .. "/env/dist/etc" }).playerbots,
                                                                         false)
-- }}}

os.execute("rm -rf '" .. WORK .. "'")

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
