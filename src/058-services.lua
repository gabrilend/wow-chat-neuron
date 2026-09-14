--------------------------------------------------------------------------------
-- 058-services.lua
--
-- The programs this world is made of: whether each is running, and how to start
-- it.
--
-- Everything here is about the MACHINE rather than about the world. Nothing in
-- this file reads a character or writes a row; it asks which ports are held and
-- runs the deployment's own scripts. That separation is why it can answer while
-- the database is down, which is exactly when somebody most wants an answer.
--
-- DETECTION IS BY PORT, always. Not by pid file -- one left behind by a killed
-- process names something that is gone. Not by process name -- matching on a
-- script's filename also matches the shell running the command, because that
-- filename is in the shell's own command line, and that has killed this
-- project's terminal twice. A held port is a fact about the machine that
-- nothing can lie about.
--
-- NOTHING HERE IS STARTED SILENTLY. Every launch writes to a log the menu links
-- to, because a server started from a web page is a server whose output nobody
-- saw -- and the output is where "it started and immediately died" lives.
--------------------------------------------------------------------------------

local Services = {}

-- {{{ shell_quote(text)
local function shell_quote(text)
    return "'" .. tostring(text):gsub("'", "'\\''") .. "'"
end
-- }}}

-- {{{ holder_of(port)
-- The pid holding a port, or nil.
local function holder_of(port)
    local pipe = io.popen(string.format(
        "ss -lptnH 'sport = :%d' 2>/dev/null", port), "r")
    if not pipe then return nil end

    local line = pipe:read("*a") or ""
    pipe:close()

    return tonumber(line:match("pid=(%d+)"))
end
-- }}}

-- {{{ Services.of(handle)
-- The list, built against a particular deployment.
--
-- Ports are read from the deployment's own configs where they are configurable,
-- rather than written here -- a second copy of a port number is a second thing
-- to be wrong, and being wrong about it looks exactly like the server being
-- down.
function Services.of(handle)
    local deployment = handle.root
    local profile    = handle.profile
    -- The install tree is the config directory's parent, whatever shape the
    -- deployment has: wow-chat puts it at installed-files-<profile>/etc, a
    -- stock build at env/dist/etc. Derived from the one path the handle
    -- already resolved rather than rebuilt from the convention.
    local installed  = (handle.config_dir or ""):match("^(.*)/etc/?$")
                       or string.format("%s/installed-files-%s", deployment, profile)
    local logs       = handle.neuron_root .. "/tmp/shared-memory"

    -- Captured output is named PER DEPLOYMENT.
    --
    -- It was one file per service, which meant switching deployments left the
    -- previous one's capture sitting under the new one's name -- the log
    -- button lit up, showed somebody else's worldserver, and nothing said so.
    -- That is exactly the lie the button was gated to prevent, arrived at from
    -- a direction the gate could not see.
    --
    -- The tag is the deployment's path with its separators flattened, so a
    -- directory listing is readable and no two deployments collide without
    -- needing a hash nobody can read back.
    local tag        = handle.root:gsub("^/", ""):gsub("[^%w]+", "-")
    local captured   = logs .. "/" .. tag

    os.execute("mkdir -p " .. shell_quote(captured))

    -- ONE LOG PER SERVICE, and it is stdout.
    --
    -- There were two, shown one above the other with a divider between them,
    -- and the second was almost always the interesting one. The config says
    -- why:
    --
    --     Appender.Console=1,4,0,"1 9 3 6 5 8"
    --     Appender.Server=2,5,0,Server.log,w
    --     Logger.root=2,Console Server
    --
    -- BOTH appenders are attached to the same loggers, so every record the
    -- server writes goes to both places. Server.log is a strict SUBSET of
    -- stdout, and stdout additionally carries the lines printed before logging
    -- was configured, whatever the launch script said, and anything that goes
    -- straight to the terminal without passing through a logger -- which is
    -- where a crash ends up.
    --
    -- So there was never a reason to read the appender's file. Two panes and a
    -- divider, to show a subset above the whole thing.
    --
    -- The appender's own file still exists and the server still writes it. It
    -- is simply not what neuron reads.
    local server_logs = string.format("%s/logs-%s", deployment, profile)

    -- Ports come off the handle now, read from the server's own config when
    -- the deployment was resolved. Nothing here opens a config file, and
    -- nothing hardcodes a number.

    -- {{{ command_for(name, detected) / directory_for(name)
    -- What to run, and where to run it from.
    --
    -- A WRAPPER SCRIPT AND A BARE BINARY ARE THE SAME THING HERE, and nothing
    -- needs to know which it was handed. This deployment's wrappers do four
    -- things beyond finding the binary: resolve the profile, symlink logs into
    -- RAM, check the database is up, and change to the install directory. Only
    -- the last matters to a bare binary -- AzerothCore looks for its config at
    -- `../etc` relative to the binary, and a stock `DataDir = "."` is relative
    -- to the working directory -- so neuron changes directory itself, and a
    -- script that also does it is unharmed. The database check is already in
    -- the menu, which will not enable start until mysql is up.
    --
    -- The working directory defaults to the directory holding the command,
    -- which is right for a binary in bin/ and irrelevant to a script.
    local set = (handle.services or {})

    local function command_for(name, detected)
        local override = set[name] and set[name].command
        return override and shell_quote(override) or detected
    end

    -- {{{ environment_for(name)
    -- What has to be in the environment before the command will work.
    --
    -- This deployment's worldserver wrapper sets LD_LIBRARY_PATH to its own
    -- mysql lib directory, because the server links against a client library
    -- that is not the system's. A wrapper does that for itself; a bare binary
    -- has to be told, and there is nowhere else to say it.
    local function environment_for(name)
        return (set[name] or {}).environment
    end
    -- }}}

    local function directory_for(name)
        local entry = set[name] or {}
        if entry.directory then return entry.directory end

        local command = entry.command
        return command and command:match("^(.*)/[^/]+$") or nil
    end
    -- }}}

    local defined = {
        -- {{{ mysql
        {
            name  = "mysql",
            what  = "",
            port  = handle.mysql_port,
            start = command_for("mysql",
                shell_quote(deployment .. "/scripts/start-mysql")),
            directory = directory_for("mysql"),
            log    = captured .. "/mysql.log",
            -- mysqld reads no commands from its standard input -- it speaks
            -- the MySQL protocol on a socket. The pipe exists so its console
            -- does not spin; there is nothing on the other end of it listening.
            console = nil,
            console_why = "mysqld takes no commands on standard input -- it "
                       .. "speaks the MySQL protocol on a socket. neuron's own "
                       .. "levers reach it through the cold hand.",
            stop  = "signal",
            -- Stopping the database out from under a running worldserver is a
            -- way to corrupt a world. Rather than refuse -- which left a
            -- greyed-out button explaining nothing -- it states what has to go
            -- first, and the page walks through them in order.
            requires_down = { "authserver", "worldserver" },
            stop_why = "The worldserver holds the world in memory and writes it "
                    .. "to this database. Taking the database away underneath it "
                    .. "is how a world gets corrupted, so these stop in order.",
        },
        -- }}}

        -- {{{ authserver
        {
            name  = "authserver",
            -- Both this script and start-mysql decide whether MySQL is running
            -- by looking for its PID FILE -- which mysqld writes only once it
            -- has finished initialising. Start this a second after mysql and it
            -- sees no PID file, concludes MySQL is down, and starts a SECOND
            -- mysqld that cannot lock ibdata1 and fails in a loop.
            --
            -- So this waits for the port, which is true the moment it is true.
            requires_up = { "mysql" },
            what  = "",
            port  = handle.auth_port,
            start = command_for("authserver",
                shell_quote(deployment .. "/scripts/authserver")),
            directory = directory_for("authserver"),
            log    = captured .. "/authserver.log",
            stop  = "signal",
            console = "stdin",
        },
        -- }}}

        -- {{{ worldserver
        {
            name  = "worldserver",
            requires_up = { "mysql" },
            what  = "",
            port  = handle.world_port,
            start = command_for("worldserver",
                shell_quote(deployment .. "/scripts/worldserver")),
            directory = directory_for("worldserver"),
            log    = captured .. "/worldserver.log",
            -- A signal kills it where it stands and loses everything since the
            -- last save. The right way is to ask it to shut down, which saves
            -- first -- and that goes through the live hand, not through a
            -- process signal.
            stop  = "graceful",
            console = "stdin",
            stop_why = "The worldserver holds the world in MEMORY and writes it "
                    .. "down periodically. Killed, it loses everything since its "
                    .. "last save. It is asked to shut down instead, which saves "
                    .. "first and takes about half a minute.",
        },
        -- }}}

        -- {{{ ollama
        -- The local model, as a service rather than as a thing you check.
        --
        -- It used to have a `check` button that made a request and reported
        -- whether anything answered. That is a strange shape for something you
        -- can simply start: the other three servers are not "checked", they are
        -- started and their lamp says what happened, and their log says why
        -- when it did not. This is the same kind of thing and now looks like
        -- it.
        --
        -- It depends on NOTHING and nothing depends on it. It does not care
        -- which profile is active, it holds no world, and stopping it loses
        -- only whatever a model was midway through saying. So no requires_up,
        -- no requires_down, and a plain signal to stop.
        (function()
            -- Host and port taken from the ADDRESS neuron is configured to
            -- dial, and handed to ollama as OLLAMA_HOST.
            --
            -- Without that they disagree by default: ollama binds
            -- 127.0.0.1:11434 whatever the configuration says, so starting it
            -- from here produced a server on one port and a menu watching
            -- another, reporting "starting" forever about something that had
            -- finished starting a minute ago.
            --
            -- Setting it means the two cannot drift: the address is the
            -- configuration, and the configuration is what gets bound.
            local bench = (handle.asking or {}).bench
            local host  = bench and bench.url
                and bench.url:match("^https?://([^:/]+)") or "127.0.0.1"
            local port  = tonumber(bench and bench.url
                and bench.url:match("^https?://[^:/]+:(%d+)")) or 11434

            -- A LAN address means it must listen on every interface, not on
            -- the one address -- otherwise a second machine on the network
            -- cannot reach it even though the address names this one.
            local bind = (host == "127.0.0.1" or host == "localhost")
                and host or "0.0.0.0"

            return {
            name  = "ollama",
            -- Excluded from the "stop everything before switching profile"
            -- sweep. A profile names a set of databases and an installed tree;
            -- ollama has neither, holds no world, and would come back saying
            -- exactly the same things. Stopping it would cost a loaded model
            -- and several seconds for no reason at all.
            profile_agnostic = true,
            what  = "",
            port  = port,
            start = string.format("env OLLAMA_HOST=%s:%d ollama serve",
                bind, port),
            log   = captured .. "/ollama.log",
            stop  = "signal",
            -- `ollama serve` reads nothing from standard input. It is a
            -- server; what it takes is HTTP.
            console = nil,
            console_why = "ollama serve takes no commands on standard input. "
                       .. "Everything it does arrives as HTTP, which is how "
                       .. "neuron asks it things.",
            }
        end)(),
        -- }}}
    }

    -- Where each one's launch writes its process-group id. Attached here rather
    -- than built where it is needed, because `Services.state` is handed a
    -- service and not a handle, and threading the handle through every caller
    -- to rebuild a path the service could simply carry is the wrong trade.
    for _, service in ipairs(defined) do
        service.group = string.format("%s/group-%s.pid", captured, service.name)
        service.environment = environment_for(service.name)

        -- CAN THIS ACTUALLY BE RUN? Asked of the command itself, so a start
        -- button that leads nowhere is disabled with a reason rather than
        -- pressed and then failing in a log nobody has open yet.
        --
        -- The first word of the command is the program. Everything after it is
        -- arguments, and `env VAR=x ollama serve` has `env` as its program,
        -- which is on every machine -- so a service launched that way is
        -- reported runnable and finds out about `ollama` from its own log. That
        -- is the honest answer: this checks what it can see.
        local program = (service.start or ""):match("^'?([^'%s]+)")

        if not program then
            service.runnable = false
            service.why_not  = service.name .. " has no start command."
        else
            local probe = io.popen(string.format(
                "command -v %s >/dev/null 2>&1 && echo yes",
                "'" .. program:gsub("'", "'\\''") .. "'"), "r")
            local answer = probe and probe:read("*l") or nil
            if probe then probe:close() end

            service.runnable = answer == "yes"

            -- An explicit if. `runnable and nil or "..."` always yields the
            -- string, because `and nil` is falsy and `or` then takes the right
            -- side -- so every service came back runnable AND carrying a
            -- reason it was not. Same trap as the pointer check in the
            -- transcript reader, written a second time by the same hand.
            if service.runnable then
                service.why_not = nil
            else
                service.why_not = string.format(
                    "%s is not a program this user can run.", program)
            end
        end

        -- Where the SERVER writes its own log, when it says. Used only when
        -- neuron did not start the service and so captured nothing: the port
        -- can say something is up while the captured file is a stale record of
        -- an earlier run, and a log that lies about which run it describes is
        -- worse than a greyed-out button.
        if handle.server_logs_dir and handle.server_logs_dir ~= "" then
            local named = ({
                worldserver = "Server.log",
                authserver  = "Auth.log",
            })[service.name]

            if named then
                service.server_log = handle.server_logs_dir .. "/" .. named
            end
        end
    end

    return defined
end
-- }}}

-- {{{ group_of(service)
-- The process group a launch recorded, if it is still alive.
--
-- The file lives in the RAM tier, so it is empty after a reboot -- which is
-- correct, because nothing it named is running after one either. A stale entry
-- from a process that has since exited is checked rather than trusted.
local function group_of(service)
    local file = io.open(service.group or "", "r")
    if not file then return nil end

    local pid = tonumber((file:read("*l") or ""):match("%d+"))
    file:close()

    if not pid then return nil end

    -- Is anything still IN the group, rather than: is the group LEADER alive.
    --
    -- The leader is the launcher, which becomes the deployment's wrapper
    -- script -- and the wrapper runs the server as a child and waits. Kill the
    -- leader and the child is orphaned but very much still running, still
    -- loading maps, and about to bind a port. Asking after the leader answered
    -- "nothing is starting" about a server that was.
    local pipe = io.popen("pgrep -g " .. pid .. " 2>/dev/null | head -1", "r")
    if not pipe then return nil end

    local any = tonumber((pipe:read("*l") or ""):match("%d+"))
    pipe:close()

    if any then return pid end

    return nil
end
-- }}}

-- {{{ Services.state(service)
-- Up or down, and who holds the port.
function Services.state(service)
    local holder = holder_of(service.port)

    if holder then
        return { up = true, pid = holder, port = service.port }
    end

    -- STARTING is a third state, and leaving it out is why the start button
    -- flickered.
    --
    -- Up was decided by "does something hold the port". A worldserver takes
    -- half a minute to load vmaps before it binds anything, so through all of
    -- that it was reported as down -- the page re-enabled start, and pressing
    -- it again launched a SECOND one. Stop was greyed out for the same reason,
    -- so the only way to abort a start you regretted was a terminal.
    --
    -- Found by the PROCESS GROUP the launch recorded, not by searching for a
    -- command line.
    --
    -- Searching was the obvious way and it was wrong twice over. `pgrep -f`
    -- matches whole command lines including the shell io.popen started to run
    -- it, so it found itself and returned a pid that had already exited. And
    -- once that was fixed with the usual bracket trick, it found the
    -- deployment's WRAPPER script -- which runs `./worldserver` as a child and
    -- waits, rather than exec'ing it -- so stopping killed the wrapper and left
    -- the server loading. It then bound its port and reported itself up, which
    -- is exactly the sequence somebody watching would describe as "I pressed
    -- stop and it kept starting".
    local group = group_of(service)

    if group then
        return { up = false, starting = true, pid = group,
                 group = group, port = service.port }
    end

    return { up = false, port = service.port }
end
-- }}}

-- {{{ Services.chat_windows(handle, from, to)
-- Which chat windows are open, by walking the ports they use.
--
-- Windows are found rather than registered, so one somebody started by hand in
-- a terminal shows up beside one the menu started. A registry would list what
-- the menu believes and this lists what is true.
function Services.chat_windows(handle, from, to)
    local found = {}

    for port = (from or 7879), (to or 7889) do
        local holder = holder_of(port)
        if holder then
            table.insert(found, { port = port, pid = holder,
                url = string.format("http://127.0.0.1:%d", port) })
        end
    end

    return found
end
-- }}}

-- {{{ Services.free_port(handle, from, to)
-- The next port with nothing on it, for a new window.
function Services.free_port(handle, from, to)
    for port = (from or 7879), (to or 7889) do
        if not holder_of(port) then return port end
    end
    return nil
end
-- }}}

-- {{{ Services.start(handle, service)
-- Launch it, detached, with everything it says going to its log.
--
-- Returns immediately. Whether it actually came up is answered by asking the
-- port a moment later, not by whether this returned -- a process that started
-- and instantly died is still a process for a moment, and reporting success on
-- that is how somebody stares at a browser waiting for a server that is gone.
function Services.start(handle, service)
    if Services.state(service).up then
        return false, string.format(
            "%s is already listening on port %d.", service.name, service.port)
    end

    if not service.start then
        return false, string.format(
            "%s has no start command configured.", service.name)
    end

    os.execute(string.format("mkdir -p %s",
        shell_quote(handle.neuron_root .. "/tmp/shared-memory")))

    -- The launch goes through a small script written to the RAM tier rather
    -- than being handed to os.execute directly, and the reason is a bug that
    -- silently broke every start button:
    --
    -- os.execute runs its argument with /bin/sh, which on this machine is
    -- dash. The stdin redirection below is bash's process-substitution syntax.
    -- dash answers "Syntax error: redirection unexpected", os.execute returns
    -- as though nothing were wrong, and NOTHING LAUNCHES -- no error anywhere,
    -- the port never opens, and the page counts seconds forever.
    --
    -- Writing the bash into a file and running that file with bash removes both
    -- the shell mismatch and the nested-quoting problem. It also leaves the
    -- exact command on disk, which is worth having when a server will not start.
    --
    -- Why the redirection at all: without it the worldserver's console reads
    -- EOF immediately, prints its prompt, reads EOF again, and spins -- 2.8
    -- million lines of "AC> " in one startup. `< /dev/null` does not help; that
    -- IS an instant EOF.
    --
    -- A FIFO opened READ-WRITE (`0<>`) is the trick. Opening it that way never
    -- blocks, and reads block forever because the file itself holds a writer --
    -- so the console waits, exactly as it would on an idle terminal.
    --
    -- This replaced `0< <(sleep infinity)`, which worked and left a `sleep`
    -- process behind for every launch, forever, because `exec` replaced the
    -- shell that would have cleaned it up. A fix that leaks a process per use
    -- is a fix with a countdown on it.
    local launcher = string.format("%s/tmp/shared-memory/launch-%s.sh",
        handle.neuron_root, service.name)

    local file = io.open(launcher, "w")
    if not file then
        return false, string.format(
            "cannot write the launcher for %s at %s -- the RAM tier is missing, "
         .. "and it is empty after every reboot.", service.name, launcher)
    end

    local pipe = string.format("%s/tmp/shared-memory/stdin-%s",
        handle.neuron_root, service.name)

    file:write(string.format(
        "#!/bin/bash\n"
     .. "# Written by neuron. Runs %s with a standard input that never\n"
     .. "# delivers, so its console does not spin on EOF printing prompts.\n"
     .. "rm -f %s\n"
     .. "mkfifo %s\n"
     .. "# stdbuf forces LINE buffering on the server's output.\n"
     .. "#\n"
     .. "# These servers log to stdout as well as to their own file, and stdout\n"
     .. "# redirected to a file is block-buffered by libc -- four kilobytes at a\n"
     .. "# time. So the log stayed empty through an entire startup and then\n"
     .. "# arrived all at once when the process exited and flushed. Somebody\n"
     .. "# watching a server start saw nothing until they stopped it.\n"
     .. "#\n"
     .. "# The launcher's own pid, written before it becomes the server.\n"
     .. "#\n"
     .. "# Started under setsid, so this pid is also the PROCESS GROUP of\n"
     .. "# everything the launch produces. That matters because the\n"
     .. "# deployment's own wrapper scripts do NOT exec the binary -- they run\n"
     .. "# `./worldserver` as a child and wait -- so a launch is two processes,\n"
     .. "# and killing the one whose command line you can find leaves the other\n"
     .. "# running. Killing the group gets both.\n"
     .. "echo $$ > %s\n"
     .. "# The redirect goes to the launcher's OWN file, never to the server's\n"
     .. "# log. It used to point at the appender's file, and then TWO things\n"
     .. "# owned that file: the shell's descriptor, writing from offset zero,\n"
     .. "# and the server's log appender, writing from wherever it had got to.\n"
     .. "# Two offsets, one file. The result was lines cut mid-word and\n"
     .. "# overwritten by the other writer -- the first line of Server.log read\n"
     .. "# 'AzerothCore rev. ... (Playerbot b' and then jumped into the middle\n"
     .. "# of a different sentence.\n"
     .. "%s"
     .. "exec stdbuf -oL -eL %s > %s 2>&1 0<> %s\n",
        service.name,
        shell_quote(pipe), shell_quote(pipe),
        shell_quote(service.group),
        -- The working directory, when one is known. A bare AzerothCore binary
        -- finds its config at ../etc relative to itself and reads DataDir
        -- relative to here, so running it from the wrong place fails in a way
        -- that reads as a missing install.
        (function()
            local lines = {}
            for key, value in pairs(service.environment or {}) do
                table.insert(lines, string.format("export %s=%s\n",
                    key, shell_quote(value)))
            end
            table.sort(lines)
            if service.directory then
                table.insert(lines, "cd " .. shell_quote(service.directory) .. "\n")
            end
            return table.concat(lines)
        end)(),
        service.start, shell_quote(service.log), shell_quote(pipe)))
    file:close()

    os.execute("chmod +x " .. shell_quote(launcher))

    -- setsid: its own session, so its own process group, so `kill -- -PID`
    -- reaches every process the launch produced and nothing else. Without it
    -- the group is shared with the menu, and killing the group would kill the
    -- menu.
    os.remove(service.group)
    os.execute(string.format("setsid nohup bash %s > /dev/null 2>&1 &",
        shell_quote(launcher)))

    return true, string.format("Starting %s...", service.name)
end
-- }}}

-- {{{ Services.stop(handle, service)
-- Stop it, in the way that service should be stopped.
--
-- Three kinds, and the difference is the whole point of the field:
--
--   "signal"    a plain TERM. Fine for something holding nothing.
--   "graceful"  ask it to shut down over SOAP so it saves first.
--   nil         no stop offered at all, because doing it from here is a
--               mistake and a button would invite it.
function Services.stop(handle, service)
    local state = Services.state(service)

    if not state.up and not state.starting then
        return false, service.name .. " is not running."
    end

    -- STILL STARTING: a signal, whatever its stop method says.
    --
    -- The graceful stop asks the worldserver to shut down over SOAP, and a
    -- worldserver that has not finished loading is not listening for SOAP yet
    -- -- so the polite request has nowhere to go and the only thing that ends
    -- it is a signal. There is nothing to lose by that: it has not loaded the
    -- world, so it has nothing unsaved.
    if state.starting then
        -- The whole GROUP. A negative pid means "every process in this group",
        -- and the group is the launcher plus the deployment's wrapper plus the
        -- server the wrapper is waiting on. Killing one of those three is what
        -- made stop look like it did nothing.
        -- TERM first, then KILL, because a worldserver loading maps does not
        -- answer TERM. AzerothCore installs a handler and defers it until it
        -- reaches a point where stopping is safe, and that point is after the
        -- load -- so a polite signal during startup is noted and ignored, the
        -- wrapper dies, and the server carries on alone.
        --
        -- Two seconds is generous for a process that has nothing to save. Then
        -- KILL, which nothing can defer.
        os.execute(string.format(
            "kill -TERM -%d 2>/dev/null; sleep 2; kill -KILL -%d 2>/dev/null",
            state.group, state.group))

        return true, string.format(
            "%s was still starting, so it and everything it had launched were "
         .. "stopped (group %d). A server loading maps does not answer a "
         .. "polite signal, so it was asked and then made to. It had not "
         .. "finished loading the world, so there was nothing unsaved to lose.",
            service.name, state.group)
    end

    if not service.stop then
        return false, service.stop_why
            or (service.name .. " cannot be stopped from here.")
    end

    if service.stop == "graceful" then
        local LiveHand = dofile(handle.neuron_root .. "/src/003-live-hand.lua")

        -- Five seconds, not thirty.
        --
        -- Thirty is the right courtesy for a live realm with people standing in
        -- it, and it is the wrong number for a button on an operator's menu:
        -- the person pressing it is the person who would have been warned. The
        -- world is saved either way -- that is what makes this graceful rather
        -- than a signal -- and the delay buys nothing but waiting.
        local answer, why = LiveHand.execute(handle, "server shutdown 5")

        if not answer then
            return false, string.format(
                "Could not ask %s to shut down.\n  %s\n\n"
             .. "  %s\n\n"
             .. "  It is still running. Stopping it any other way from here "
             .. "would lose whatever has happened since its last save, so this "
             .. "refuses rather than falling back to a signal.",
                service.name, tostring(why),
                service.stop_why or "")
        end

        return true, string.format(
            "%s was asked to shut down in 5 seconds. It saves first; anyone "
         .. "still logged in gets a countdown.", service.name)
    end

    os.execute(string.format("kill %d", state.pid))
    return true, string.format("Sent %s (PID %d) a stop signal.",
        service.name, state.pid)
end
-- }}}

-- {{{ ANSI
-- The eight colours a terminal knows, plus their bright forms.
--
-- The worldserver writes escape sequences into its log because it is written to
-- be read in a terminal, and a browser shows them as garbage -- ESC[32m appears
-- as a stray character and a bracket in front of every line.
--
-- Stripping them would be easier and would throw away meaning: the server uses
-- red for errors and yellow for warnings, which is exactly the information
-- somebody scanning a startup log wants. So they are translated rather than
-- removed.
local ANSI = {
    ["30"] = "#4a4a4a", ["31"] = "#ff6040", ["32"] = "#40ff40", ["33"] = "#ffd100",
    ["34"] = "#6090ff", ["35"] = "#ff80ff", ["36"] = "#40e0e0", ["37"] = "#d8d2c4",
    ["90"] = "#8a8375", ["91"] = "#ff8060", ["92"] = "#80ff80", ["93"] = "#ffe060",
    ["94"] = "#80b0ff", ["95"] = "#ffa0ff", ["96"] = "#80f0f0", ["97"] = "#ffffff",
}
-- }}}

-- {{{ Services.colourise(text)
-- Terminal escape sequences into HTML, with everything else escaped first.
--
-- Order matters: the HTML escaping happens BEFORE the spans are inserted, so a
-- log line containing a literal < is shown rather than becoming markup, and the
-- spans this adds are not themselves escaped away.
function Services.colourise(text)
    local escaped = text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")

    local open = 0

    local coloured = escaped:gsub("\27%[([%d;]*)m", function(codes)
        local piece = {}

        for code in codes:gmatch("[^;]+") do
            if code == "0" or code == "" then
                if open > 0 then
                    table.insert(piece, string.rep("</span>", open))
                    open = 0
                end
            elseif ANSI[code] then
                table.insert(piece, '<span style="color:' .. ANSI[code] .. '">')
                open = open + 1
            end
            -- Bold, underline and the rest are dropped rather than translated.
            -- They carry no meaning the server actually uses, and a log full of
            -- half-honoured styling reads worse than one with none.
        end

        return table.concat(piece)
    end)

    -- Anything left unclosed at the end of the text. A tail cuts the log
    -- mid-stream, so an unterminated colour is the normal case rather than a
    -- malformed one, and unbalanced spans would leak into the rest of the page.
    if open > 0 then coloured = coloured .. string.rep("</span>", open) end

    -- Any escape sequence that is not a colour -- cursor moves, clear-line --
    -- would still show as garbage. Removed after the colours are handled, so
    -- this cannot eat one.
    return (coloured:gsub("\27%[[%d;]*[A-Za-z]", ""))
end
-- }}}

-- {{{ Services.say(handle, service, command)
-- Type at a running server's console, through the pipe it was started with.
--
-- THE PIPE IS THE CONSOLE. The launcher gives each server a FIFO as its
-- standard input so its console does not spin on EOF -- and a FIFO can be
-- written to as well as read from. Anything put in it arrives at the server
-- exactly as if it had been typed at the terminal it was started from, because
-- that is precisely what it is.
--
-- This replaced sending GM commands over SOAP. SOAP works and returns its
-- output, which is why the live hand still uses it for operations -- but it is
-- a worldserver-only feature and it made the authserver look like it had no
-- console at all. It has the same console every process has; nothing was
-- offering it a way in.
--
-- Nothing comes BACK through a pipe. The answer appears in the log, which the
-- page is already following twice a second -- which is also how a terminal
-- works, so it reads correctly rather than merely functioning.
--
-- An EMPTY command is sent as a bare newline, deliberately. A console that
-- answers a blank line with a fresh prompt is a console that is alive, and that
-- is the cheapest health check there is.
function Services.say(handle, service, command)
    if service.console ~= "stdin" then
        return nil, service.console_why
            or (service.name .. " has no console that can be reached from here.")
    end

    local pipe = string.format("%s/tmp/shared-memory/stdin-%s",
        handle.neuron_root, service.name)

    -- Is the running process actually reading THIS pipe?
    --
    -- Checking only that the pipe file exists is not enough: it survives from
    -- whichever earlier run created it, so a server started from a terminal
    -- passes the check and the write vanishes into a pipe nobody reads -- while
    -- the page reports "sent". Which is what happened.
    local state = Services.state(service)

    -- BOTH SIDES RESOLVED before they are compared.
    --
    -- /proc/<pid>/fd/0 gives the path with every symlink already followed, and
    -- the path built above goes through two of them: `tmp` points at
    -- /tmp/<project>, and `tmp/shared-memory` inside it points at
    -- /dev/shm/<project>. So one side read
    --
    --     /mnt/.../wow-chat-neuron/tmp/shared-memory/stdin-worldserver
    --
    -- and the other read
    --
    --     /dev/shm/wow-chat-neuron/stdin-worldserver
    --
    -- -- the same file, spelled differently, compared as strings and found
    -- unequal. Every command typed at a running worldserver was refused with
    -- "it is not reading a console this menu can write to", which is a true
    -- sentence about a false comparison.
    local resolve = function(path)
        local probe = io.popen(string.format("readlink -f %s 2>/dev/null",
            "'" .. tostring(path):gsub("'", "'\\''") .. "'"), "r")
        if not probe then return path end
        local answer = probe:read("*l") or path
        probe:close()
        return answer
    end

    local reading = io.popen(string.format(
        "readlink -f /proc/%d/fd/0 2>/dev/null", state.pid or 0), "r")
    local stdin = reading and (reading:read("*l") or "") or ""
    if reading then reading:close() end

    if stdin ~= resolve(pipe) then
        return nil, string.format(
            "%s is not reading a console this menu can write to.\n"
         .. "  Its standard input is %s.\n"
         .. "  A server started from a terminal keeps that terminal's console. "
         .. "Stop it and start it from here, and its console arrives with it.",
            service.name, stdin ~= "" and stdin or "not readable")
    end

    -- The leading dot a game master types is stripped: the console wants the
    -- command without it, and typing it the way you would in the game is what
    -- everybody will do.
    command = tostring(command or ""):gsub("^%s*%.?%s*", ""):gsub("[\r\n]", "")

    -- Opening a FIFO for writing BLOCKS until a reader is there. A server that
    -- has died is never going to read again, so the write waits forever and
    -- takes the menu with it -- which is exactly what happened the first time
    -- this was tried against a stopped mysql.
    --
    -- Two guards, because neither alone is enough. The port check catches the
    -- ordinary case; the timeout catches a server still holding its port and no
    -- longer reading.
    if not Services.state(service).up then
        return nil, string.format(
            "%s is not running, so nothing is reading its console.",
            service.name)
    end

    -- The command goes through a file rather than through nested shell
    -- quoting. A game master command can contain quotes, and building a
    -- three-deep quoted string to carry one is how a stray apostrophe in a
    -- character name becomes a syntax error in a shell.
    local scratch = pipe .. ".send"
    local file = io.open(scratch, "w")
    if not file then
        return nil, "cannot write to the RAM tier to stage the command."
    end
    file:write(command .. "\n")
    file:close()

    os.execute(string.format(
        "( timeout 1 sh -c 'cat %s > %s' ; rm -f %s ) >/dev/null 2>&1 &",
        shell_quote(scratch), shell_quote(pipe), shell_quote(scratch)))

    if command == "" then
        return "(sent a bare newline -- if a fresh prompt appears in the log "
            .. "below, it is alive)"
    end

    return "." .. command .. "  -- sent; the answer appears in the log below"
end
-- }}}

-- {{{ Services.tail(path, lines)
-- The end of a log, for showing what a server said as it started or failed.
--
-- Bare console prompts are dropped. The worldserver prints "AC> " whenever its
-- console is ready for input, and with no terminal attached that is constantly
-- -- so a tail of the last few hundred lines is otherwise entirely prompts and
-- none of what the server actually said. The launch above stops them being
-- produced; this stops the ones already written from hiding everything else.
function Services.tail(path, lines)
    local pipe = io.popen(string.format(
        "grep -av '^AC> *$' %s 2>/dev/null | tail -n %d",
        shell_quote(path), lines or 40), "r")
    if not pipe then return "(cannot read " .. path .. ")" end

    local text = pipe:read("*a") or ""
    pipe:close()

    if text == "" then
        return "(" .. path .. " is empty -- nothing has been written to it yet)"
    end

    return text
end
-- }}}

return Services
