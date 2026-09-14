--------------------------------------------------------------------------------
-- 002-cold-hand.lua
--
-- Runs SQL against the deployment's own MySQL, over the deployment's own unix
-- socket, using the deployment's own client binary. Returns rows as Lua tables.
--
-- This is the hand that works when the world is DOWN. It reaches every row of
-- every table, which is both why it is useful and why it is dangerous: with the
-- worldserver up, a write to a logged-in character's row is silently discarded
-- when the server next flushes its in-memory copy over the top. Nothing errors.
-- Guarding against that is 004-liveness.lua's job, not this file's -- this file
-- is a transport and stays out of policy.
--
-- Statements are built as SHAPES with `?` holes plus a separate list of values.
-- Callers never concatenate. That is injection hygiene, but the bigger half is
-- that a shape with forty pairs of values is reviewable by a person, and forty
-- fully-built statements are not.
--
-- See issues/102-the-cold-hand-sql.md for the blueprint.
--------------------------------------------------------------------------------

local ColdHand = {}

-- {{{ shell_quote(text)
-- Wrap a value for safe use as a single shell argument.
--
-- Single-quoting is total in POSIX shells: every character inside single quotes
-- is literal. The only thing that cannot appear is a single quote itself, so an
-- embedded quote is closed, escaped, and reopened -- the standard '\'' dance.
--
-- Everything this module hands to the shell goes through here. A deployment
-- path containing a space is not exotic and should not break the tool.
local function shell_quote(text)
    return "'" .. tostring(text):gsub("'", "'\\''") .. "'"
end
-- }}}

-- {{{ sql_escape(value)
-- Render one Lua value as a SQL literal.
--
-- The type decides the rendering, and each branch means something different to
-- the resulting statement:
--
--   nil     -> NULL          the column is being cleared, or was never set
--   boolean -> 1 / 0         MySQL has no boolean; TINYINT is the convention,
--                            and `online` in the characters table is one
--   number  -> bare literal  integers printed without a decimal point, because
--                            "%g" on 12345678 would render 1.2345678e+07 and
--                            a GUID written in scientific notation matches
--                            nothing
--   string  -> quoted        with backslash and quote escaped; NUL and the
--                            control characters MySQL cares about handled too
--
-- Anything else is a programming error in an operation and errors loudly here,
-- at the point of the mistake, rather than becoming a syntax error later whose
-- message points at the wrong place.
local function sql_escape(value)
    local kind = type(value)

    if value == nil then
        return "NULL"

    elseif kind == "boolean" then
        return value and "1" or "0"

    elseif kind == "number" then
        -- Integral values print as integers. math.floor comparison rather than
        -- a modulo test so that negative numbers behave.
        if value == math.floor(value) and value == value and value ~= math.huge
           and value ~= -math.huge then
            return string.format("%d", value)
        end
        return string.format("%.17g", value)

    elseif kind == "string" then
        local escaped = value
            :gsub("\\", "\\\\")
            :gsub("'",  "\\'")
            :gsub('"',  '\\"')
            :gsub("\n", "\\n")
            :gsub("\r", "\\r")
            :gsub("\26", "\\Z")
            :gsub("%z", "\\0")
        return "'" .. escaped .. "'"
    end

    error("002-cold-hand: cannot put a " .. kind .. " into a SQL statement. "
       .. "Bind values must be nil, boolean, number, or string.")
end
-- }}}

-- {{{ bind(statement, values)
-- Substitute `?` placeholders with escaped values, left to right.
--
-- A count mismatch is a programming error in the calling operation, and it is
-- caught HERE -- where the shape and the values are both in hand and the message
-- can name both counts -- rather than downstream as a MySQL syntax error whose
-- text points at a character offset in a string nobody wrote by hand.
--
-- `?` inside a string literal in the shape would be substituted wrongly. No
-- current caller does that, and the fix if one ever needs to is to pass the
-- literal as a bind value, which is what bind values are for.
function ColdHand.bind(statement, values)
    values = values or {}

    local wanted = 0
    for _ in statement:gmatch("%?") do
        wanted = wanted + 1
    end

    local given = 0
    for _ in pairs(values) do
        given = given + 1
    end

    if wanted ~= given then
        error(string.format(
            "002-cold-hand: statement has %d placeholder(s) but %d value(s) were given\n  %s",
            wanted, given, statement))
    end

    local index = 0
    -- gsub's replacement function returns the literal text to substitute. The
    -- escaped value may itself contain '%' characters, which would be treated
    -- as capture references if returned from a pattern-based replacement, so
    -- the function form is required rather than a convenience.
    local bound = statement:gsub("%?", function()
        index = index + 1
        return sql_escape(values[index])
    end)

    return bound
end
-- }}}

-- {{{ placeholders(count)
-- Build "?, ?, ?" for an IN clause of the given length.
--
-- The reason this exists as a helper: a roster of forty characters should be
-- ONE query with forty placeholders, not forty queries. Every list-shaped read
-- in 005-world-read.lua goes through here, and the difference is one round trip
-- against forty.
function ColdHand.placeholders(count)
    if count < 1 then
        error("002-cold-hand: placeholders(" .. tostring(count) .. ") -- an empty "
           .. "IN clause is not valid SQL. The caller should skip the query "
           .. "entirely when its list is empty.")
    end
    local parts = {}
    for _ = 1, count do
        table.insert(parts, "?")
    end
    return table.concat(parts, ", ")
end
-- }}}

-- {{{ unescape_batch_field(field)
-- Undo the escaping mysql --batch applies to field values.
--
-- In batch mode the client emits tab-separated rows and escapes the characters
-- that would otherwise break that framing: tab, newline, carriage return, and
-- the backslash used to escape them. Undoing it in one left-to-right pass
-- avoids the classic bug where unescaping "\\" first turns "\\t" into a real
-- tab.
local BATCH_UNESCAPE = {
    ["0"]  = "\0",
    ["n"]  = "\n",
    ["r"]  = "\r",
    ["t"]  = "\t",
    ["\\"] = "\\",
}

local function unescape_batch_field(field)
    return (field:gsub("\\(.)", function(character)
        return BATCH_UNESCAPE[character] or character
    end))
end
-- }}}

-- {{{ split_batch_line(line)
-- Split one tab-separated output row into its fields, unescaping each.
--
-- The literal NULL marker and a string whose value is the four characters
-- "NULL" are INDISTINGUISHABLE in batch output. This is a real limit of the
-- format, not an oversight here. It does not bite for anything neuron reads --
-- character names, coordinates, levels, GUIDs -- and if a column ever needs to
-- hold the literal text "NULL", that column must not be read through this path.
local function split_batch_line(line)
    local fields = {}
    local start  = 1
    while true do
        local tab = line:find("\t", start, true)
        if not tab then
            table.insert(fields, line:sub(start))
            break
        end
        table.insert(fields, line:sub(start, tab - 1))
        start = tab + 1
    end

    for index, field in ipairs(fields) do
        if field == "NULL" then
            fields[index] = nil
            -- A nil in the middle of an array breaks ipairs, so record the hole
            -- separately; the row builder below reads by index, not by ipairs.
            fields["null_at_" .. index] = true
        else
            fields[index] = unescape_batch_field(field)
        end
    end

    return fields
end
-- }}}

-- {{{ numeric_or_string(text)
-- Convert a field to a number when it is unambiguously one.
--
-- Two paths, and the distinction matters downstream: a GUID that stays a string
-- will not compare equal to a GUID that became a number, and a character named
-- "12" must not become the number 12. tonumber's own judgment is used, with the
-- guard that the round trip must be exact -- so "007" stays a string, because
-- turning it into 7 would lose information the database chose to keep.
local function numeric_or_string(text)
    if text == nil then
        return nil
    end
    local number = tonumber(text)
    if number and tostring(number) == text then
        return number
    end
    -- MySQL renders floats with trailing precision that tostring may not
    -- reproduce byte-for-byte; accept a numeric-looking field as a number when
    -- it matches a strict numeric pattern, which a character name never will.
    if number and text:match("^%-?%d+%.?%d*$") then
        return number
    end
    return text
end
-- }}}

-- {{{ run_client(handle, database, statement)
-- Invoke the deployment's mysql client and return its raw stdout.
--
-- The password goes through the MYSQL_PWD environment variable rather than a
-- -p flag. A -p flag is visible to every user on the machine in `ps` output for
-- as long as the process lives; an environment variable is visible only to the
-- process owner via /proc. Neither is perfect -- a defaults-file with mode 600
-- would be -- but this is one line instead of a temp-file lifecycle, and it
-- closes the hole that actually gets exploited.
--
-- Failure is detected from the client's exit status, and the two paths mean
-- different things: a non-zero exit is a real failure (bad SQL, no connection,
-- bad credentials) and is returned as an error with the client's own message,
-- which is far more useful than anything this file could invent.
local function run_client(handle, database, statement)
    if not handle.mysql_password then
        return nil, "no database password -- the deployment's secrets.conf has "
                 .. "no DB_PASS, so there is nothing to authenticate with"
    end

    -- The password goes in a mysql option file, not in the environment.
    --
    -- MYSQL_PWD was the lesser evil against a -p flag visible in `ps`, and both
    -- are avoidable: an environment variable is inherited by every child
    -- process and readable from /proc by the owner and by root. --defaults-file
    -- is the mechanism mysql provides for exactly this, and the file is mode
    -- 600 in the RAM tier.
    local Keys = dofile(handle.neuron_root .. "/src/052-keys.lua")

    local options, options_why = Keys.defaults_file(handle, handle.mysql_password)
    if not options then
        return nil, options_why
    end

    local command = table.concat({
        shell_quote(handle.mysql_binary),
        "--defaults-file=" .. shell_quote(options),
        -- HOST AND PORT, not a socket path.
        --
        -- The socket was on the handle only because this deployment happens to
        -- keep one locally, at a path built from the project root. A stock
        -- install has no such file and its config names a host and a port --
        -- which the local case also names, in the same line. So this reaches
        -- both, and a handle field disappeared rather than gaining an override.
        --
        -- `--protocol=TCP` is explicit because the client silently prefers a
        -- unix socket whenever the host is `localhost`, ignoring the port. A
        -- deployment running two servers on one machine at different ports --
        -- which is exactly what a profile switch produces -- would then reach
        -- whichever one owns the default socket.
        "--host="     .. shell_quote(handle.mysql_host),
        "--port="     .. tostring(handle.mysql_port),
        "--protocol=TCP",
        "--user="   .. shell_quote(handle.mysql_user),
        "--batch",
        "--raw",
        shell_quote(database),
        "-e", shell_quote(statement),
        "2>&1",
    }, " ")

    local pipe = io.popen(command, "r")
    if not pipe then
        return nil, "could not start " .. handle.mysql_binary
    end
    local output = pipe:read("*a")
    local ok, _, code = pipe:close()

    if not ok then
        return nil, string.format("mysql exited %s: %s",
            tostring(code), (output or ""):gsub("%s+$", ""))
    end

    return output
end
-- }}}

-- {{{ ColdHand.read(handle, database, statement, values)
-- Run a SELECT and return an array of row tables keyed by column name.
--
-- An empty result is an EMPTY ARRAY, never nil. A caller iterating a result set
-- should not have to nil-check before looping; the distinction between "no rows"
-- and "the query failed" is carried by the second return value, which is the
-- only thing that is ever nil here.
function ColdHand.read(handle, database, statement, values)
    local bound = ColdHand.bind(statement, values)

    local output, why = run_client(handle, database, bound)
    if not output then
        return nil, why
    end

    local rows = {}

    -- The first line is the column-name header. No lines at all means the query
    -- returned no rows AND no header, which mysql does for a result set with
    -- zero rows -- an empty array is the correct answer, not an error.
    local lines = {}
    for line in output:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    if #lines == 0 then
        return rows
    end

    local columns = split_batch_line(lines[1])

    for line_index = 2, #lines do
        local fields = split_batch_line(lines[line_index])
        local row = {}
        for column_index = 1, #columns do
            local name = columns[column_index]
            row[name] = numeric_or_string(fields[column_index])
        end
        table.insert(rows, row)
    end

    return rows
end
-- }}}

-- {{{ ColdHand.write(handle, database, statement, values)
-- Run a statement that changes rows. Returns the affected-row count.
--
-- A write affecting ZERO rows is reported as zero and is NOT treated as an
-- error here. Whether zero is wrong is the caller's judgment: an UPDATE that
-- matched nothing may mean the character was already where you wanted them, or
-- may mean the GUID was wrong. The transport reports the number and stays out
-- of it; the operation decides what the number means.
function ColdHand.write(handle, database, statement, values)
    local bound = ColdHand.bind(statement, values)

    -- ROW_COUNT() reports how many rows the immediately preceding statement
    -- changed. Asking for it in the same invocation keeps it in the same
    -- connection -- a second invocation would be a new connection and would
    -- report -1 for "no previous statement".
    local output, why = run_client(handle, database, bound .. "; SELECT ROW_COUNT() AS affected;")
    if not output then
        return nil, why
    end

    local affected = output:match("affected%s*\n%s*(%-?%d+)")
    if not affected then
        return nil, "could not read affected-row count from mysql output:\n" .. output
    end

    return tonumber(affected)
end
-- }}}

-- {{{ ColdHand.script(handle, database, statements, label)
-- Run many statements in ONE connection, as one transaction.
--
-- Everything else in this file is one statement per invocation, and therefore
-- one connection per statement. That is fine for single writes and wrong for two
-- situations this function exists to handle:
--
--   A TRANSACTION cannot span connections. The core wraps a character deletion
--   in one so a character is never half removed; reproducing that needs every
--   statement in the same session.
--
--   A TEMPORARY TABLE is scoped to its connection and invisible to every other
--   one. Set-shaped work -- "delete these twenty-five thousand guids from
--   thirty-nine tables" -- wants the guid list in a temporary table so each
--   deletion can say WHERE guid IN (SELECT ...) instead of carrying the list.
--   That collapses 975,000 statements into 39.
--
-- The script goes in through STDIN rather than -e, because a guid list is
-- megabytes of text and a command line is not.
--
-- Failure semantics differ from the rest of this file and it matters: the script
-- turns on the client's abort-on-error, so the FIRST failing statement stops the
-- run before COMMIT is reached. An uncommitted transaction is rolled back when
-- the connection closes, so a script that dies partway changes nothing at all.
function ColdHand.script(handle, database, statements, label)
    if not handle.mysql_password then
        return nil, "no database password -- the deployment's secrets.conf has "
                 .. "no DB_PASS, so there is nothing to authenticate with"
    end

    -- Written to the RAM tier rather than piped directly, so that a script which
    -- misbehaves can be read afterwards. It is deleted on success; a leftover
    -- file is itself a signal.
    local script_path = "/dev/shm/wow-chat-neuron/" .. (label or "script") .. ".sql"

    local file, why = io.open(script_path, "w")
    if not file then
        return nil, "cannot write the script to " .. script_path .. ": " .. tostring(why)
    end
    file:write(statements)
    file:close()

    local command = table.concat({
        "MYSQL_PWD=" .. shell_quote(handle.mysql_password),
        shell_quote(handle.mysql_binary),
        "--no-defaults",
        -- HOST AND PORT, not a socket path.
        --
        -- The socket was on the handle only because this deployment happens to
        -- keep one locally, at a path built from the project root. A stock
        -- install has no such file and its config names a host and a port --
        -- which the local case also names, in the same line. So this reaches
        -- both, and a handle field disappeared rather than gaining an override.
        --
        -- `--protocol=TCP` is explicit because the client silently prefers a
        -- unix socket whenever the host is `localhost`, ignoring the port. A
        -- deployment running two servers on one machine at different ports --
        -- which is exactly what a profile switch produces -- would then reach
        -- whichever one owns the default socket.
        "--host="     .. shell_quote(handle.mysql_host),
        "--port="     .. tostring(handle.mysql_port),
        "--protocol=TCP",
        "--user="   .. shell_quote(handle.mysql_user),
        "--batch",
        -- NO explicit stop-on-error flag is passed, and that is deliberate rather
        -- than an omission. In batch mode the client already stops at the first
        -- failing statement and exits non-zero; --force is what would make it
        -- carry on. An earlier version passed --abort-source-on-error, which
        -- this client (9.6.0) does not have, and the flag itself became the
        -- error. Verified by feeding a script with a bad statement in the
        -- middle: the statements after it do not run.
        shell_quote(database),
        "<", shell_quote(script_path),
        "2>&1",
    }, " ")

    local pipe = io.popen(command, "r")
    if not pipe then
        return nil, "could not start " .. handle.mysql_binary
    end
    local output = pipe:read("*a")
    local ok, _, code = pipe:close()

    if not ok then
        return nil, string.format(
            "the script failed at statement exit %s and was NOT committed.\n"
         .. "  The script is still at %s for inspection.\n  %s",
            tostring(code), script_path, (output or ""):gsub("%s+$", ""))
    end

    os.remove(script_path)
    return output
end
-- }}}

-- {{{ ColdHand.probe(handle)
-- Is the deployment's database reachable, and if not, why not?
--
-- Three distinguishable outcomes, because they have three different fixes and
-- the person reading the message should not have to guess which one they have:
--
--   socket_missing  no socket file at all       -> MySQL was never started
--   socket_stale    file exists, nothing behind -> a crashed server left it;
--                                                  this is the single most
--                                                  confusing state a deployment
--                                                  gets into, and it looks
--                                                  identical to "running" from
--                                                  a directory listing
--   auth_failed     connected, credentials bad  -> fix DB_PASS
--   up              a trivial query returned    -> proceed
function ColdHand.probe(handle)
    -- IS SOMETHING LISTENING, asked of the port rather than of a socket file.
    --
    -- This used to test for the socket with os.rename(path, path) -- io.open
    -- fails on a live socket with "No such device or address", because a socket
    -- cannot be opened as a stream, and would have reported a perfectly good
    -- one as missing. That was a real subtlety and it is gone with the socket:
    -- a port either accepts a connection or it does not, and the answer is the
    -- same for a local server and a remote one.
    --
    -- The connection is opened and dropped without a word spoken. Nothing is
    -- sent, nothing is read, and the server logs a connection that went away --
    -- which is what any port check looks like from the other side.
    local socket_ok, socket = pcall(require, "socket")

    if not socket_ok then
        return false, "no_socket_library",
            "luasocket is not available, so the database port cannot be "
         .. "checked. Every other part of neuron that speaks HTTP needs it too."
    end

    local probe = socket.tcp()
    probe:settimeout(handle.probe_timeout or 2)

    local connected, connect_why = probe:connect(handle.mysql_host,
                                                 handle.mysql_port)
    probe:close()

    if not connected then
        return false, "not_listening", string.format(
            "nothing is listening at %s:%d -- the deployment's MySQL has not "
         .. "been started.\n  The connection said: %s",
            handle.mysql_host, handle.mysql_port, tostring(connect_why))
    end

    local rows, why = ColdHand.read(handle, handle.db_characters, "SELECT 1 AS ok")

    if rows then
        return true, "up", nil
    end

    if why and (why:lower():find("access denied") or why:lower():find("using password")) then
        return false, "auth_failed", why
    end

    -- Listening, and refusing to answer. A MySQL still starting up accepts
    -- connections before it will serve a query, and one that is shutting down
    -- does the same on the way out -- so this is a real state and not a
    -- leftover, which is what the old "stale socket file" answer described.
    return false, "not_answering", string.format(
        "%s:%d accepted a connection and then would not answer a trivial "
     .. "query.\n  Detail: %s\n\n"
     .. "  To debug:\n"
     .. "    Is it still starting?\n"
     .. "      MySQL listens before it finishes recovering; wait and ask "
     .. "again.\n"
     .. "    Does the database named exist?\n"
     .. "      The query ran against %s.",
        handle.mysql_host, handle.mysql_port, tostring(why),
        tostring(handle.db_characters))
end
-- }}}

return ColdHand
