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
-- ABSENT IS AN ANSWER, not a failure. A profile is a wow-chat idea: one
-- deployment holding several worlds, each with its own installed tree and its
-- own three databases. A stock AzerothCore has one of everything and no file
-- naming it, and that is a perfectly good deployment -- so a missing `.profile`
-- returns nil and the caller stops suffixing database names and stops looking
-- for a per-profile install directory.
--
-- This used to be fatal, which was right when neuron drove one deployment and
-- wrong the moment it could drive any. The reasoning it was built on survives:
-- the deployment is still the authority on which profile it runs, and neuron
-- still does not keep a second copy of that answer. It simply no longer insists
-- there is one.
local function read_profile(root)
    local path = root .. "/.profile"
    local contents = read_file(path)
    if not contents then
        return nil
    end
    local profile = contents:match("^%s*([%w%-_]+)")
    if not profile then
        error("000-deployment: " .. path .. " exists and contains no profile "
           .. "name.\n  A deployment with no profiles has no such file at all; "
           .. "one that is empty or malformed is a file somebody meant to fill "
           .. "in.")
    end
    return profile
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

-- {{{ config_dir(root, profile)
-- Where the server's own .conf files are.
--
-- THE ONE PLACE A LAYOUT CONVENTION LIVES, and after this function nothing
-- else in the project encodes one. Everything the deployment needs is either
-- in those files or is one of six things no config file can answer, so getting
-- here correctly is most of the work of pointing neuron at a strange
-- deployment.
--
-- Two patterns are tried, in order, and the order is not a preference: they
-- cannot both match, because each requires a directory the other does not
-- have. A wow-chat deployment keeps one installed tree per profile; a stock
-- one has a single install prefix.
--
--     installed-files-<profile>/etc      this project
--     env/dist/etc                       a stock build's default prefix
--
-- A deployment matching neither is not refused: the config directory is one of
-- the values `config/deployment.lua` can state outright, and stating it skips
-- this function entirely. Detection is a convenience, not a gate.
local function config_dir(root, profile)
    local candidates = {}

    if profile then
        table.insert(candidates, root .. "/installed-files-" .. profile .. "/etc")
    end

    table.insert(candidates, root .. "/env/dist/etc")
    table.insert(candidates, root .. "/etc")

    for _, path in ipairs(candidates) do
        local probe = io.open(path .. "/worldserver.conf", "r")
        if probe then
            probe:close()
            return path
        end
    end

    return nil, candidates
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

-- {{{ absolute_key(neuron_root, path)
-- A key path, made absolute against neuron's own root.
--
-- Relative on purpose in the config, so that reading it tells you the key lives
-- inside this project rather than somewhere on the machine. Resolved here so
-- that nothing above ever has to know which root a relative path belongs to --
-- there are two roots in play and picking the wrong one would look for the key
-- in the deployment.
local function absolute_key(neuron_root, path)
    if not path or path == "" then return nil end
    if path:sub(1, 1) == "/" then return path end
    return neuron_root .. "/" .. path
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

-- `wanted_profile`, when given, overrides both the config and the deployment.
-- It exists so a caller can point one window or one command at a different
-- world without editing a file -- and, importantly, without leaving it edited
-- afterwards, which is how a "temporary" change becomes permanent.
function Deployment.load(wanted_profile)
    if cached_handle and not wanted_profile then
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

    -- An explicit profile in the config wins over the deployment's own, and the
    -- fact that it did is carried on the handle so every description can say so.
    -- A silent override would mean reading one world while believing you are
    -- reading another, which is the same class of mistake as the two answers
    -- disagreeing -- just arrived at from the other direction.
    -- Overrides always win, including over a detection that would later be
    -- right. A setting that quietly stops applying is worse than one that is
    -- wrong out loud: the second is a thing somebody can see and change.
    local set = config.overrides or {}

    local deployment_profile = read_profile(config.root)
    local profile   = wanted_profile or set.profile or config.profile
                      or deployment_profile

    -- {{{ the server's own configuration
    -- Read before anything is derived, because almost nothing needs deriving
    -- once it has been read. Seven fields that used to be built by gluing the
    -- profile onto a prefix are five fields of one line in here.
    local etc, tried = set.config_dir, nil
    if not etc then
        etc, tried = config_dir(config.root, profile)
    end

    if not etc then
        error("000-deployment: cannot find the server's configuration.\n\n"
           .. "  Looked for a worldserver.conf in:\n    "
           .. table.concat(tried or {}, "\n    ")
           .. "\n\n  Everything neuron needs about this deployment -- the "
           .. "database\n  connection, the ports, the level cap -- is in "
           .. "those files, so\n  there is nothing useful it can do without "
           .. "them.\n\n  To debug:\n"
           .. "    Has the server been installed, or only built?\n"
           .. "      A build leaves binaries; installing writes the configs.\n"
           .. "    Are they .conf.dist files still?\n"
           .. "      Those are templates. Copy each to the name without .dist.\n"
           .. "    Are they somewhere else entirely?\n"
           .. "      Set config_dir in config/deployment.lua and this stops\n"
           .. "      guessing.", 0)
    end

    local ServerConfig = dofile(neuron_root .. "/src/073-server-config.lua")

    -- Each file is separately settable. They are found by searching the
    -- config directory, which is the convenience; naming one outright is how a
    -- deployment that keeps them apart is reached.
    local world_path = set.worldserver_conf or (etc .. "/worldserver.conf")
    local auth_path  = set.authserver_conf  or (etc .. "/authserver.conf")

    local world_conf = ServerConfig.read(world_path)
    local auth_conf  = ServerConfig.read(auth_path)

    if not world_conf then
        error("000-deployment: cannot read " .. world_path .. "\n"
           .. "  Everything neuron needs about this deployment is in that "
           .. "file.", 0)
    end

    -- Both files carry a LoginDatabaseInfo and nothing keeps them in step, so
    -- they must agree. See ServerConfig.agree for why picking one is the
    -- tempting wrong answer.
    local login, login_why =
        ServerConfig.agree(world_conf, auth_conf, "LoginDatabaseInfo")
    if not login then
        error("000-deployment: " .. login_why, 0)
    end

    local world_db, world_why = ServerConfig.connection(world_conf, "WorldDatabaseInfo")
    if not world_db then error("000-deployment: " .. world_why, 0) end

    local chars_db, chars_why = ServerConfig.connection(world_conf, "CharacterDatabaseInfo")
    if not chars_db then error("000-deployment: " .. chars_why, 0) end

    -- Playerbots has its own database and NOTHING ASKS FOR IT. Bots are found
    -- by their account-name prefix out of the auth database, which is a
    -- property of how mod-playerbots names them rather than of where it keeps
    -- its tables. So the name was derived, carried on the handle, printed, and
    -- never used for anything.
    -- }}}

    local databases = {
        world      = world_db.database,
        characters = chars_db.database,
    }

    -- Credentials come from two files with two different owners: the
    -- deployment's secrets hold the database password (it is the deployment's
    -- database), neuron's own secrets hold the SOAP password (the GM account is
    -- neuron's identity, not the deployment's).
    -- The asking config is optional. A neuron with no config/asking.lua is a
    -- neuron that pulls its own levers and never asks anything, which is a
    -- complete and supported way to use it -- so a missing file is absence,
    -- not failure. A file that exists and is broken IS a failure, and says so.
    local asking = nil
    local asking_path = neuron_root .. "/config/asking.lua"
    local asking_file = io.open(asking_path, "r")

    if asking_file then
        asking_file:close()
        local chunk, chunk_why = loadfile(asking_path)
        if not chunk then
            error("config/asking.lua exists and will not load:\n  "
               .. tostring(chunk_why)
               .. "\n  Delete it to run without a model, or fix it.", 0)
        end
        asking = chunk()
    end

    -- secrets.conf is NOT read, and the reason is worth stating because it
    -- looks like an omission.
    --
    -- It is a wow-chat file -- AzerothCore has never heard of it -- and it is
    -- the SOURCE that scripts/generate-configs copies into the .conf files,
    -- not an alternative to them. The password lands in worldserver.conf in
    -- plaintext either way, so reading secrets.conf hides nothing. It can only
    -- differ from the generated config when somebody edited it and did not
    -- regenerate -- and in that case the SERVER is using the generated one
    -- too, so reading the config keeps neuron in step with the thing it is
    -- driving. Reading secrets.conf would make neuron the only participant
    -- using a password nothing else knows.
    --

    cached_handle = {
        neuron_root    = neuron_root,
        root           = config.root,
        profile        = profile,
        deployment_profile = deployment_profile,
        profile_overridden = profile ~= deployment_profile,
        profile_from_argument = wanted_profile ~= nil,

        -- Where the .conf files are, carried so nothing else rebuilds the
        -- path. Anything wanting a server setting -- the level cap, a port,
        -- the addon list -- asks for this rather than gluing the profile onto
        -- the root a second time.
        config_dir     = etc,
        -- How to start each server, when the detected command is wrong. Read
        -- by 058-services.lua, which no longer holds any of it in source.
        services       = config.services or {},
        -- What was stated rather than worked out, so the page can say which
        -- of its rows are claims neuron made and which are yours.
        overrides      = set,
        config_detected = set.config_dir == nil,

        -- The one thing about the database no config file names, because it is
        -- neuron's business rather than the server's: neuron runs a client
        -- binary instead of linking a driver. Detected in the deployment's own
        -- tree first, since a client from the same build cannot skew against
        -- its server, then whatever is on PATH.
        mysql_binary   = set.mysql_client or mysql_binary(config.root),

        -- Host, port, user and password all off one line of the file the
        -- server itself reads, so neuron and the server agree by construction.
        -- A value neuron computed can disagree with the server's; a value
        -- neuron read cannot.
        mysql_host     = login.host,
        mysql_port     = login.port,
        mysql_user     = login.user,
        mysql_password = login.password,
        mysql_where    = login.where,

        db_world       = databases.world,
        db_characters  = databases.characters,

        -- The auth database is NOT profile-suffixed. Accounts are shared
        -- across every profile on the machine, which is why a bot account
        -- created for one profile is visible from all of them.
        db_auth        = login.database,

        -- How playerbot accounts are named. mod-playerbots creates its fleet
        -- under a configurable prefix and RNDBOT is its default; the live
        -- deployment has 2210 of them. This is a heuristic, not a fact the
        -- schema records -- there is no "is a bot" column anywhere -- so a
        -- human who names their account RNDBOTTLES would be misread. Stated
        -- plainly rather than hidden, because a wrong answer here silently
        -- puts a person in a roster meant for bots.
        bot_account_prefix = config.bot_account_prefix or "RNDBOT",

        -- The SOAP endpoint is in the server's config too. Overridable
        -- because a deployment reached through a tunnel or a container answers
        -- somewhere other than where it believes it listens.
        soap_url       = set.soap_url or config.soap_url or (function()
            local ip   = ServerConfig.value(world_conf, "SOAP.IP") or "127.0.0.1"
            local port = ServerConfig.value(world_conf, "SOAP.Port") or "7878"
            return string.format("http://%s:%s/", ip, port)
        end)(),
        soap_enabled   = ServerConfig.value(world_conf, "SOAP.Enabled") == "1",
        soap_account   = set.soap_account or config.soap_account,
        -- PATHS to credentials, never the credentials themselves.
        --
        -- Nothing that receives this handle receives a secret. The one function
        -- that needs one opens its file at the moment of use and lets it go --
        -- see 052-keys.lua for why that is different in kind from a config
        -- value, rather than merely tidier.
        --
        -- Relative paths resolve against neuron's own root, so a key never
        -- accidentally names something in the deployment.
        soap_key_path  = absolute_key(neuron_root, set.soap_key or config.soap_key),
        api_key_path   = absolute_key(neuron_root, set.api_key or config.api_key),
        asking         = asking,

        -- Where ALE looks for scripts. Only meaningful when the module is
        -- installed, and profile-shaped, so it is nil on a deployment with no
        -- profiles unless somebody says otherwise.
        lua_custom_dir = set.lua_custom_dir
            or (profile and lua_custom_dir(config.root, profile) or nil),

        -- The level cap, read here rather than by whoever wants it. The
        -- conversation loop used to open the config itself, building the
        -- wow-chat path a second time in a file with nothing to do with
        -- deployment layout -- so on a stock install it would have reported
        -- the cap unreadable from a deployment where it is plainly there.
        max_player_level =
            tonumber(ServerConfig.value(world_conf, "MaxPlayerLevel")),
        max_player_level_where =
            ServerConfig.where(world_conf, "MaxPlayerLevel"),

        -- Ports, off the same files. Nothing hardcodes a number any more.
        world_port = tonumber(ServerConfig.value(world_conf, "WorldServerPort")),
        auth_port  = tonumber(ServerConfig.value(auth_conf, "RealmServerPort")),

        -- Where the SERVER writes its own log, for the case neuron did not
        -- start it and so captured no output of its own.
        server_logs_dir = ServerConfig.value(world_conf, "LogsDir"),

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
    if not handle.profile then
        table.insert(lines, "profile    : none -- this deployment has one "
            .. "world and one set of databases")
    elseif handle.profile_overridden then
        table.insert(lines, "profile    : " .. handle.profile
            .. "   (chosen in neuron's config; the deployment itself is set to '"
            .. tostring(handle.deployment_profile) .. "')")
    else
        table.insert(lines, "profile    : " .. handle.profile
            .. "   (read from the deployment)")
    end
    table.insert(lines, "databases  : " .. handle.db_world)
    table.insert(lines, "             " .. handle.db_characters)
    table.insert(lines, string.format("mysql      : %s:%d as %s   (%s)",
        handle.mysql_host, handle.mysql_port, handle.mysql_user,
        handle.mysql_where))
    table.insert(lines, "soap       : " .. tostring(handle.soap_url)
                     .. " as " .. tostring(handle.soap_account))
    return table.concat(lines, "\n")
end
-- }}}

return Deployment
