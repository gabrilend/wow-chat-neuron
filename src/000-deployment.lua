--------------------------------------------------------------------------------
-- 000-deployment.lua
--
-- Resolves "which world" into a table of concrete facts: absolute paths, the
-- three database names, and the credentials for both hands. Every operation in
-- the project takes this table as its first argument and reads its paths out of
-- it, so that no operation anywhere builds a path or a database name itself.
--
-- Built once and cached for the process. Building it reads three files off disk;
-- doing that per operation would make a forty-step plan perform two hundred
-- pointless reads for an answer that cannot have changed.
--
-- See issues/101-deployment-handle-and-configuration.md for the blueprint.
--------------------------------------------------------------------------------

local Deployment = {}

-- {{{ project_root()
-- Where this copy of neuron lives on disk.
--
-- Derived from the path of this very source file rather than hardcoded, so the
-- project can be moved or checked out twice without editing anything. The Lua
-- debug info gives us ".../src/000-deployment.lua"; two directory levels up is
-- the project root.
--
-- Falls back to nothing. If the path cannot be determined, that is an error and
-- not a thing to guess at, because guessing produces a neuron that reads a
-- different project's configuration and reports confidently about the wrong
-- world.
local function project_root()
    local source = debug.getinfo(1, "S").source
    if source:sub(1, 1) ~= "@" then
        error("000-deployment: cannot determine project root -- this file was "
           .. "loaded from a string rather than from disk, so there is no path "
           .. "to work back from")
    end
    local this_file = source:sub(2)
    local src_dir   = this_file:match("^(.*)/[^/]+$")
    if not src_dir then
        error("000-deployment: source path '" .. this_file .. "' has no directory part")
    end
    local root = src_dir:match("^(.*)/[^/]+$")
    if not root then
        error("000-deployment: cannot find parent of '" .. src_dir .. "'")
    end
    return root
end
-- }}}

-- {{{ read_file(path)
-- Whole-file read. Returns contents, or nil plus a reason.
--
-- The two paths out of here mean different things to the caller: contents means
-- the file was there and readable; nil means it was not, and the caller decides
-- whether that is fatal. Every current caller decides that it is.
local function read_file(path)
    local handle = io.open(path, "r")
    if not handle then
        return nil, "cannot open " .. path
    end
    local contents = handle:read("*a")
    handle:close()
    return contents
end
-- }}}

-- {{{ read_profile(root)
-- Reads the deployment's own `.profile` file, which names the active profile.
--
-- This is read rather than configured on purpose. The deployment is the
-- authority on which profile it is running; a second copy of that answer in
-- neuron's config would be a second thing to keep in sync, and the failure mode
-- of them disagreeing is silent writes to the wrong database.
local function read_profile(root)
    local path = root .. "/.profile"
    local contents, why = read_file(path)
    if not contents then
        error("000-deployment: " .. why .. "\n"
           .. "  The deployment at " .. root .. " has no .profile file, so there\n"
           .. "  is no way to know which profile is active, and therefore no way\n"
           .. "  to know which databases to talk to.")
    end
    local profile = contents:match("^%s*([%w%-_]+)")
    if not profile then
        error("000-deployment: " .. path .. " does not contain a profile name")
    end
    return profile
end
-- }}}

-- {{{ read_shell_settings(path)
-- Parses a shell-fragment settings file -- lines of KEY=value, with optional
-- quoting and # comments -- into a plain table.
--
-- Parsed rather than sourced. Sourcing would execute whatever is in the file,
-- which is exactly the kind of unbounded reach this whole project exists to
-- avoid; a settings file should be data, and treating it as data is how it
-- stays data.
--
-- A missing file returns an empty table rather than erroring. Callers that
-- require a particular key report that key as missing, which is a far more
-- useful message than "no secrets file".
local function read_shell_settings(path)
    local settings = {}
    local contents = read_file(path)
    if not contents then
        return settings
    end
    for line in contents:gmatch("[^\r\n]+") do
        -- Skip blanks and comments. Everything else must look like KEY=value;
        -- a line that does not is ignored rather than fatal, because these
        -- files belong to the deployment and may carry things we do not know
        -- about.
        if not line:match("^%s*#") and not line:match("^%s*$") then
            local key, value = line:match("^%s*([%w_]+)%s*=%s*(.*)$")
            if key then
                value = value:gsub("%s+$", "")
                -- Strip one layer of matching quotes if present.
                local unquoted = value:match('^"(.*)"$') or value:match("^'(.*)'$")
                settings[key] = unquoted or value
            end
        end
    end
    return settings
end
-- }}}

-- {{{ database_names(profile)
-- Maps a profile name onto the three databases that profile uses.
--
-- The deployment derives its database names from the profile by exactly this
-- rule, which is why neuron derives rather than configures them. If the
-- convention ever changes, it changes here, once.
--
-- Confirmed against the deployment's own database directory: acore_world_vanilla,
-- acore_characters_vanilla, acore_playerbots_vanilla all exist on disk.
local function database_names(profile)
    return {
        world      = "acore_world_"      .. profile,
        characters = "acore_characters_" .. profile,
        playerbots = "acore_playerbots_" .. profile,
    }
end
-- }}}

-- {{{ mysql_binary(root)
-- The deployment ships its own MySQL. We use that client and that socket, never
-- the system-wide one.
--
-- This matters more than it looks. This machine runs a second, unrelated MySQL
-- instance serving different data. Connecting to the wrong one would succeed,
-- return plausible-looking results, and be entirely wrong. The socket path is
-- what makes that mistake impossible, and the binary comes from the same tree
-- so that client and server versions cannot skew.
local function mysql_binary(root)
    return root .. "/mysql/installed-files/bin/mysql"
end
-- }}}

-- {{{ lua_custom_dir(root, profile)
-- Where the deployment's ALE looks for custom Lua scripts.
--
-- This is the resident hand's install target: scripts written here are loaded
-- by the worldserver, in-process, on its tick budget. The deployment symlinks
-- a per-profile source directory into this location at install time, so writing
-- here writes into the profile's script corpus.
local function lua_custom_dir(root, profile)
    return root .. "/installed-files-" .. profile .. "/bin/lua_scripts/custom"
end
-- }}}

-- {{{ Deployment.load()
-- Assembles the handle. Cached after the first call.
--
-- Every failure here is fatal and named. There is no default deployment, no
-- guessed path, and no assumption of a profile: a fallback at this layer would
-- silently point the entire project at the wrong world, and per the standing
-- project position a fallback is a warning and a warning is an error.
local cached_handle = nil

function Deployment.load()
    if cached_handle then
        return cached_handle
    end

    local neuron_root = project_root()

    local config_path = neuron_root .. "/config/deployment.lua"
    local chunk, load_error = loadfile(config_path)
    if not chunk then
        error("000-deployment: cannot read " .. config_path .. "\n  " .. tostring(load_error))
    end
    local config = chunk()

    if not config or not config.root then
        error("000-deployment: " .. config_path .. " does not name a deployment root")
    end

    local profile   = read_profile(config.root)
    local databases = database_names(profile)

    -- Credentials come from two files with two different owners: the
    -- deployment's secrets hold the database password (it is the deployment's
    -- database), neuron's own secrets hold the SOAP password (the GM account is
    -- neuron's identity, not the deployment's).
    local deployment_secrets = read_shell_settings(config.root .. "/secrets.conf")
    local neuron_secrets     = read_shell_settings(neuron_root .. "/secrets.conf")

    cached_handle = {
        neuron_root    = neuron_root,
        root           = config.root,
        profile        = profile,

        mysql_binary   = mysql_binary(config.root),
        mysql_socket   = config.root .. "/mysql/databases/mysql.sock",
        mysql_user     = deployment_secrets.DB_USER or "root",
        mysql_password = deployment_secrets.DB_PASS,

        db_world       = databases.world,
        db_characters  = databases.characters,
        db_playerbots  = databases.playerbots,

        soap_url       = config.soap_url,
        soap_account   = config.soap_account,
        soap_password  = neuron_secrets.NEURON_SOAP_PASSWORD,

        lua_custom_dir = lua_custom_dir(config.root, profile),

        probe_timeout  = config.probe_timeout_seconds or 3,

        receipts_dir   = neuron_root .. "/tmp/shared-memory/receipts",
    }

    return cached_handle
end
-- }}}

-- {{{ Deployment.forget()
-- Drops the cache. Only for tests, which need to load a handle, change
-- something on disk, and load it again.
function Deployment.forget()
    cached_handle = nil
end
-- }}}

-- {{{ Deployment.describe(handle)
-- A human-readable summary of what the handle points at. Used by the status
-- board and by any error report that wants to say which world it is talking
-- about -- naming the world in an error is how you notice you are pointed at
-- the wrong one.
function Deployment.describe(handle)
    local lines = {}
    table.insert(lines, "deployment : " .. handle.root)
    table.insert(lines, "profile    : " .. handle.profile)
    table.insert(lines, "databases  : " .. handle.db_world)
    table.insert(lines, "             " .. handle.db_characters)
    table.insert(lines, "             " .. handle.db_playerbots)
    table.insert(lines, "mysql      : " .. handle.mysql_socket)
    table.insert(lines, "soap       : " .. tostring(handle.soap_url)
                     .. " as " .. tostring(handle.soap_account))
    return table.concat(lines, "\n")
end
-- }}}

return Deployment
