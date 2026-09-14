--------------------------------------------------------------------------------
-- 073-server-config.lua
--
-- Reading AzerothCore's own configuration files.
--
-- WHY THIS EXISTS. Almost everything neuron used to derive by string
-- concatenation is written down already, in the files the server itself reads.
-- The database host, port, user, password and name; the SOAP endpoint; every
-- port; the maximum character level; where the maps are. Deriving them from a
-- directory-naming convention meant encoding one deployment's habits into
-- neuron, which is why a stock AzerothCore install was refused.
--
-- Reading them instead has a second property worth more than the portability:
-- neuron and the server agree by construction, because they are reading the
-- same line of the same file. A value neuron computed can disagree with the
-- server's; a value neuron read cannot.
--
-- THE FORMAT. Plain `key = value` lines, `#` for comments, values sometimes
-- quoted. Every setting appears twice in a stock file -- once inside the
-- comment block that documents it, and once as the live setting -- so a naive
-- scan finds the documentation's example first and reports the default as
-- though it were configured. Only lines with nothing before the key count.
--------------------------------------------------------------------------------

local ServerConfig = {}

-- {{{ ServerConfig.read(path)
-- One config file, as a table of setting name to { value, line }.
--
-- The line number is kept because it is what an error message needs. "Two
-- files disagree about the database" is a report somebody cannot act on;
-- "worldserver.conf line 121 says 3307 and authserver.conf line 232 says 3306"
-- is one they can.
function ServerConfig.read(path)
    local file = io.open(path, "r")
    if not file then
        return nil, "cannot read " .. path
    end

    local found, number = {}, 0

    for line in file:lines() do
        number = number + 1

        -- Anchored at the start of the line. The documentation block above
        -- every setting contains lines like "#        Default: 3306", and a
        -- pattern that allowed leading text would match those -- reporting the
        -- documented default as the configured value, which is right often
        -- enough to be trusted and wrong exactly when somebody has changed
        -- something.
        local key, value = line:match("^([%w%._]+)%s*=%s*(.-)%s*$")

        if key then
            -- Quotes are optional in this format and carry no meaning.
            value = value:gsub('^"(.*)"$', "%1")
            found[key] = { value = value, line = number, file = path }
        end
    end

    file:close()
    return found
end
-- }}}

-- {{{ ServerConfig.value(settings, key)
-- One setting's value, or nil.
local function value_of(settings, key)
    local entry = settings and settings[key]
    return entry and entry.value or nil
end

ServerConfig.value = value_of
-- }}}

-- {{{ ServerConfig.where(settings, key)
-- Where a setting was read from, as "worldserver.conf line 121".
--
-- Every value neuron shows carries this. "neuron worked this out" and "the
-- server says this" are different claims and the page has to be able to tell
-- them apart, or the standing position that a fallback is a warning has
-- nothing to stand on.
function ServerConfig.where(settings, key)
    local entry = settings and settings[key]
    if not entry then return nil end

    local name = entry.file:match("([^/]+)$") or entry.file
    return string.format("%s line %d", name, entry.line)
end
-- }}}

-- {{{ ServerConfig.connection(settings, key)
-- A `*DatabaseInfo` line, taken apart.
--
--     LoginDatabaseInfo = "127.0.0.1;3307;ritz;menardi;acore_auth"
--
-- Five fields, semicolon separated, in this order in every AzerothCore that
-- has ever been built: host, port, user, password, database. This one line
-- replaces seven fields neuron used to derive -- the socket path, the client
-- user and password out of a separate secrets file, and the four database
-- names built by gluing the profile onto a prefix.
--
-- Returns the five, plus where they were read, or nil and why not.
function ServerConfig.connection(settings, key)
    local raw = value_of(settings, key)

    if not raw then
        return nil, string.format(
            "no %s in the configuration.\n"
         .. "  Every AzerothCore worldserver.conf and authserver.conf has one. "
         .. "A file without it is not one of those, or is a .dist template that "
         .. "was never turned into a real config.", key)
    end

    local pieces = {}
    for piece in (raw .. ";"):gmatch("(.-);") do
        table.insert(pieces, piece)
    end

    if #pieces < 5 then
        return nil, string.format(
            "%s is not five semicolon-separated fields.\n"
         .. "  Read back: %s\n"
         .. "  Expected:  host;port;user;password;database\n"
         .. "  From:      %s",
            key, raw, ServerConfig.where(settings, key))
    end

    local port = tonumber(pieces[2])

    if not port then
        return nil, string.format(
            "%s has '%s' where its port should be, which is not a number.\n"
         .. "  From: %s", key, pieces[2], ServerConfig.where(settings, key))
    end

    return {
        host     = pieces[1],
        port     = port,
        user     = pieces[3],
        password = pieces[4],
        database = pieces[5],
        where    = ServerConfig.where(settings, key),
    }
end
-- }}}

-- {{{ ServerConfig.agree(first, second, key)
-- Two files' answers for the same setting, or a refusal naming both.
--
-- `authserver.conf` and `worldserver.conf` each carry a `LoginDatabaseInfo`
-- and nothing in AzerothCore keeps them in step. Picking one and getting on
-- with it is the tempting answer and the wrong one: neuron would reach a
-- different database from one of the two servers it is driving, every read
-- would succeed, and nothing would look wrong until an account existed in one
-- place and not the other.
--
-- So they must agree, and when they do not, the error names both files, both
-- lines and both values -- everything needed to go and fix it.
function ServerConfig.agree(first, second, key)
    local one, why_one = ServerConfig.connection(first, key)
    if not one then return nil, why_one end

    -- The second file may simply not have the setting, which is not a
    -- disagreement. Only two stated answers can disagree.
    if not second or not second[key] then
        return one
    end

    local two, why_two = ServerConfig.connection(second, key)
    if not two then return nil, why_two end

    for _, field in ipairs({ "host", "port", "user", "password", "database" }) do
        if tostring(one[field]) ~= tostring(two[field]) then
            return nil, string.format(
                "two configuration files disagree about %s.\n\n"
             .. "  %s\n    says %s is %s\n\n"
             .. "  %s\n    says %s is %s\n\n"
             .. "  Nothing has been read from either. They describe the same "
             .. "database and neuron cannot tell which of them the servers are "
             .. "actually using -- and picking one would mean reaching a "
             .. "different database from one of the two servers, with every "
             .. "read succeeding and nothing looking wrong.\n\n"
             .. "  To debug:\n"
             .. "    Was one of them edited by hand?\n"
             .. "      In this deployment both are generated; regenerating "
             .. "restores agreement.\n"
             .. "    Is one of them a leftover from a different install?\n"
             .. "      Compare their whole database blocks, not just this line.",
                key,
                one.where, field, tostring(one[field]),
                two.where, field, tostring(two[field]))
        end
    end

    return one
end
-- }}}

return ServerConfig
