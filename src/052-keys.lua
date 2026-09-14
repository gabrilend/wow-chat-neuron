--------------------------------------------------------------------------------
-- 052-keys.lua
--
-- A credential is a key. It lives in its own file, alone, with its own
-- permissions, and it is READ AT THE POINT OF USE -- never loaded into a config
-- table, never carried in a handle, never put in an environment variable.
--
-- WHY THIS IS DIFFERENT FROM WHAT WAS HERE BEFORE:
--
-- A conf file is a settings file that happens to have a secret in it. The
-- secret then travels: it is parsed into a table, the table is passed to
-- whoever asks, and every function that receives the handle receives the
-- password whether it wanted it or not. Nothing is guarding it at that point --
-- it is just a string in a structure that gets printed, logged, serialised and
-- passed around.
--
-- A key is not a setting. It is an artifact you POINT AT. The handle carries a
-- path; the one function that needs the credential opens the file, uses what is
-- inside, and lets it go. Nothing between the file and the socket ever holds it.
--
-- An environment variable is worse than a conf file, not better: it is
-- inherited by every child process, and on Linux it is readable from /proc by
-- the owner and by root. `MYSQL_PWD` was chosen here originally as the lesser
-- evil against a `-p` flag visible in `ps`, and both are avoidable.
--
-- WHAT A KEY FILE LOOKS LIKE:
--
--     secrets/soap.key        one line, the credential, nothing else
--     secrets/api.key         no name, no equals sign, no comments
--
-- Mode 600, in a directory with mode 700. Anything readable by anybody else is
-- REFUSED rather than warned about -- a key another account can read is already
-- a key that other account has.
--------------------------------------------------------------------------------

local Keys = {}

-- {{{ shell_quote(text)
local function shell_quote(text)
    return "'" .. tostring(text):gsub("'", "'\\''") .. "'"
end
-- }}}

-- {{{ mode_of(path)
-- The file's permission bits, as three digits, or nil.
--
-- Shelled out because LuaJIT ships no stat and this project takes no
-- dependencies. It is called once per credential per use, which is rare enough
-- that a process is cheaper than a dependency.
local function mode_of(path)
    local pipe = io.popen("stat -c '%a' " .. shell_quote(path) .. " 2>/dev/null", "r")
    if not pipe then return nil end
    local mode = (pipe:read("*l") or ""):gsub("%s", "")
    pipe:close()
    return mode ~= "" and mode or nil
end
-- }}}

-- {{{ Keys.read(path, what)
-- The credential, for immediate use. `what` names it in any refusal.
--
-- Returns the contents and nothing else -- no table, no wrapper, nothing that
-- could be stored somewhere by accident and still look like a normal value.
function Keys.read(path, what)
    what = what or "a key"

    if not path or path == "" then
        return nil, string.format(
            "no path is configured for %s.\n"
         .. "  A credential is a file this points at, not a value written into a\n"
         .. "  config. Set its path in config/deployment.lua.", what)
    end

    local mode = mode_of(path)

    if not mode then
        return nil, string.format(
            "%s is missing. Create it:\n"
         .. "\n"
         .. "      printf '%%s' 'the-credential' > %s\n"
         .. "      chmod 600 %s\n"
         .. "\n"
         .. "  The file holds the credential and nothing else -- no name, no\n"
         .. "  equals sign, no quotes, no comment. The path is already\n"
         .. "  configured, so nothing else needs changing.",
            what, path, path)
    end

    -- Only the owner. A key the group or the world can read is a key they
    -- already have, so this is a refusal and not a warning -- per the standing
    -- position that a warning is an error.
    local group_and_other = tonumber(mode:sub(-2))

    if group_and_other and group_and_other ~= 0 then
        local directory = path:match("^(.*)/[^/]*$") or "."

        -- The FIX comes first and the reasoning after it.
        --
        -- This message used to open with "has mode 644 and can be read by
        -- somebody else", which is a diagnosis rather than an instruction --
        -- and worse, only its first line survived to the chat window, so the
        -- chmod that would have fixed it was never shown at all. A message
        -- whose actionable half can be truncated away is a message that has to
        -- put the action first.
        return nil, string.format(
            "%s cannot be used yet. Run this:\n"
         .. "\n"
         .. "      chmod 700 %s\n"
         .. "      chmod 600 %s\n"
         .. "\n"
         .. "  Why: the file is mode %s, which lets other accounts on this\n"
         .. "  machine read it. A key somebody else can read is a key they\n"
         .. "  already have, so it is refused rather than used with a warning --\n"
         .. "  a warning about a leaked credential is a credential that leaked.\n"
         .. "  On a machine only you use this is a formality. The check cannot\n"
         .. "  tell the difference, and the cost of humouring it is one command.",
            what, directory, path, mode)
    end

    local file = io.open(path, "r")
    if not file then
        return nil, string.format(
            "%s at %s cannot be opened, though it exists with mode %s.\n"
         .. "  Most likely it belongs to another user. neuron reads it as\n"
         .. "  whoever runs neuron.", what, path, mode)
    end

    local contents = file:read("*a")
    file:close()

    -- Trailing newline stripped, because a file written with `printf` and a file
    -- written by an editor differ by exactly one character and the difference
    -- is invisible. A credential that fails only when it came out of an editor
    -- is the worst kind of intermittent.
    local credential = (contents or ""):gsub("%s+$", "")

    if credential == "" then
        return nil, string.format(
            "%s at %s is empty.\n"
         .. "  The file exists and has the right permissions and holds nothing,\n"
         .. "  which usually means a redirect wrote it before the value was\n"
         .. "  ready.", what, path)
    end

    if credential:find("=") then
        return nil, string.format(
            "%s holds a config line rather than a key. Rewrite it as just the\n"
         .. "  secret:\n"
         .. "\n"
         .. "      printf '%%s' 'the-part-after-the-equals-sign' > %s\n"
         .. "\n"
         .. "  Why: %s contains an equals sign.\n"
         .. "  A key file holds the credential ALONE. If the line is\n"
         .. "  'NEURON_API_KEY=sk-abc123', the file should hold 'sk-abc123'.\n"
         .. "  Guessed at rather than refused, a password becomes the literal\n"
         .. "  string 'NEURON_API_KEY=sk-abc123' and every request fails with an\n"
         .. "  authentication error nobody can explain.",
            what, path, path)
    end

    return credential
end
-- }}}

-- {{{ Keys.present(path)
-- Is there a usable key here? For the status board, which must say whether a
-- credential exists WITHOUT ever holding it.
--
-- Returns: true, or false plus a one-line reason. Never the credential.
function Keys.present(path, what)
    local credential, why = Keys.read(path, what or "the key")
    if credential then return true end

    -- The WHOLE message, not its first line.
    --
    -- It used to return only the first line, on the reasoning that a status
    -- board wants one. What actually happened is that the chat window showed
    -- "has mode 644 and can be read by somebody else" and threw away the chmod
    -- that would have fixed it -- leaving a person told they had a problem and
    -- not told what to do, which is the worst of both.
    return false, why
end
-- }}}

-- {{{ Keys.defaults_file(handle, password)
-- A mysql option file, for handing a password to the client without an
-- environment variable and without a -p flag.
--
-- The three ways to give mysql a password, worst to best:
--
--   -p<password>     visible in `ps` to every user on the machine, for as long
--                    as the query runs
--   MYSQL_PWD=...    inherited by children, readable from /proc by the owner
--                    and by root
--   --defaults-file  a file only the owner can read, which is the mechanism
--                    mysql provides for exactly this
--
-- Written to the RAM tier once per process and reused, because writing it per
-- query would be a file create and delete around every SELECT.
local cached_defaults = nil

function Keys.defaults_file(handle, password)
    if cached_defaults then return cached_defaults end

    local path = string.format("%s/tmp/shared-memory/mysql-%d.cnf",
        handle.neuron_root, os.time())

    local file, why = io.open(path, "w")
    if not file then
        return nil, string.format(
            "cannot write a mysql option file at %s\n  %s\n"
         .. "  Without it the password would have to go in an environment\n"
         .. "  variable or on the command line, and neither is done here.",
            path, tostring(why))
    end

    file:write("[client]\npassword=" .. password .. "\n")
    file:close()

    -- Written first, then narrowed. There is a moment between the two where the
    -- file is world-readable, which is why it is in the RAM tier under a
    -- directory nobody else has reason to walk, and why mysql itself REFUSES a
    -- world-writable option file.
    os.execute("chmod 600 " .. shell_quote(path))

    cached_defaults = path
    return path
end
-- }}}

return Keys
