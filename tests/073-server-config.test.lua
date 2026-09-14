--------------------------------------------------------------------------------
-- tests/073-server-config.test.lua
--
-- Reading AzerothCore's own configuration.
--
-- WHY THIS MATTERS MORE THAN IT LOOKS: everything neuron used to derive from a
-- directory-naming convention is read from these files now. The database
-- connection, every port, the level cap. Getting the parse wrong does not
-- produce an error -- it produces neuron confidently reaching the wrong
-- database, which is the failure the whole deployment handle exists to prevent.
--------------------------------------------------------------------------------

local ROOT   = "/mnt/mtwo/games/azeroth-core/wow-chat-neuron"
local Config = dofile(ROOT .. "/src/073-server-config.lua")

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
          .. "bedafefb-6053-4b5b-b904-cb058c036837/scratchpad/config-test"
os.execute("rm -rf '" .. WORK .. "'")
os.execute("mkdir -p '" .. WORK .. "'")

-- {{{ a config shaped like a real one
-- Including the documentation block above each setting, because that is what
-- makes this parse hard: every setting appears twice, once as prose and once
-- for real, and a scan that is not anchored finds the prose first.
local file = io.open(WORK .. "/worldserver.conf", "w")
file:write([[
###############################################################################
#    LoginDatabaseInfo
#        Description: Database connection settings.
#        Example:     "127.0.0.1;3306;acore;acore;acore_auth"
#        Default:     "127.0.0.1;3306;acore;acore;acore_auth"

LoginDatabaseInfo     = "127.0.0.1;3307;ritz;menardi;acore_auth"
WorldDatabaseInfo     = "127.0.0.1;3307;ritz;menardi;acore_world_vanilla"

#    MaxPlayerLevel
#        Default:     80
MaxPlayerLevel = 40

SOAP.Enabled = 1
SOAP.Port = 7878
WorldServerPort = 4462
]])
file:close()

local world = Config.read(WORK .. "/worldserver.conf")
-- }}}

-- {{{ the documentation is not the setting
-- The single most important property here. Every one of these values appears
-- in a comment above itself, as an Example or a Default, and taking one of
-- those would be right often enough to be trusted and wrong exactly when
-- somebody has changed something -- which is every deployment worth driving.
check("the live setting wins over its own documentation",
    Config.value(world, "LoginDatabaseInfo"),
    "127.0.0.1;3307;ritz;menardi;acore_auth")

check("and over a documented default",
    Config.value(world, "MaxPlayerLevel"),                                "40")
-- }}}

-- {{{ a connection line, taken apart
local login, why = Config.connection(world, "LoginDatabaseInfo")

check("the line parses",                              login ~= nil,      true)
check("host",                                         login.host, "127.0.0.1")
check("port is a number, not the text of one",        login.port,        3307)
check("user",                                         login.user,      "ritz")
check("password",                                     login.password, "menardi")
check("database",                                     login.database, "acore_auth")
check("and it says where it came from",
    login.where:find("worldserver.conf line 7", 1, true) ~= nil,         true)
-- }}}

-- {{{ where a value came from
check("provenance names the file and the line",
    Config.where(world, "MaxPlayerLevel"),         "worldserver.conf line 12")
check("and is nil for a setting that is not there",
    Config.where(world, "NoSuchSetting"),                                 nil)
-- }}}

-- {{{ a line that is not five fields
local broken = io.open(WORK .. "/broken.conf", "w")
broken:write('LoginDatabaseInfo = "127.0.0.1;3307;ritz"\n')
broken:close()

local short, short_why = Config.connection(Config.read(WORK .. "/broken.conf"),
                                           "LoginDatabaseInfo")
check("three fields is refused",                      short,              nil)
check("and the message shows what was read",
    short_why:find("127.0.0.1;3307;ritz", 1, true) ~= nil,               true)
check("and what was expected",
    short_why:find("host;port;user;password;database", 1, true) ~= nil,  true)
-- }}}

-- {{{ a port that is not a number
local lettered = io.open(WORK .. "/lettered.conf", "w")
lettered:write('LoginDatabaseInfo = "127.0.0.1;three;ritz;menardi;acore_auth"\n')
lettered:close()

local bad, bad_why = Config.connection(Config.read(WORK .. "/lettered.conf"),
                                       "LoginDatabaseInfo")
check("a lettered port is refused",                   bad,                nil)
check("naming what sat where the port should be",
    bad_why:find("'three'", 1, true) ~= nil,                             true)
-- }}}

-- {{{ two files that agree
local twin = io.open(WORK .. "/authserver.conf", "w")
twin:write('LoginDatabaseInfo = "127.0.0.1;3307;ritz;menardi;acore_auth"\n')
twin:close()

local auth = Config.read(WORK .. "/authserver.conf")
local agreed = Config.agree(world, auth, "LoginDatabaseInfo")
check("agreement returns the value",                  agreed.database, "acore_auth")
-- }}}

-- {{{ two files that disagree
-- Picking one is the tempting wrong answer: neuron would reach a different
-- database from one of the two servers it drives, every read would succeed,
-- and nothing would look wrong until an account existed in one place and not
-- the other.
local other = io.open(WORK .. "/other.conf", "w")
other:write('LoginDatabaseInfo = "127.0.0.1;3306;acore;acore;acore_auth"\n')
other:close()

local refused, refusal =
    Config.agree(world, Config.read(WORK .. "/other.conf"), "LoginDatabaseInfo")

check("disagreement is refused rather than resolved", refused,            nil)
check("both files are named",
    refusal:find("worldserver.conf", 1, true) ~= nil
        and refusal:find("other.conf", 1, true) ~= nil,                  true)
check("both values are shown",
    refusal:find("3307", 1, true) ~= nil
        and refusal:find("3306", 1, true) ~= nil,                        true)
check("and it says nothing was read from either",
    refusal:find("Nothing has been read", 1, true) ~= nil,               true)
-- }}}

-- {{{ one file having the setting and the other not is not a disagreement
-- Only two stated answers can disagree. A file that is silent about the
-- database is not making a claim about it.
local silent = io.open(WORK .. "/silent.conf", "w")
silent:write("SomethingElse = 1\n")
silent:close()

check("silence is not disagreement",
    (Config.agree(world, Config.read(WORK .. "/silent.conf"),
                  "LoginDatabaseInfo")).port,                            3307)
-- }}}

-- {{{ a missing file, and a missing setting
check("a file that is not there says so",
    (select(2, Config.read(WORK .. "/nothing.conf"))):find("cannot read", 1, true) ~= nil,
                                                                        true)

local absent, absent_why = Config.connection(world, "PlayerbotsDatabaseInfo")
check("a setting that is not there is refused",       absent,             nil)
check("and the message says which one",
    absent_why:find("PlayerbotsDatabaseInfo", 1, true) ~= nil,           true)
-- }}}

os.execute("rm -rf '" .. WORK .. "'")

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
