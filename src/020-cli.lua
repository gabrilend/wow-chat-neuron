--------------------------------------------------------------------------------
-- 020-cli.lua
--
-- The command line. One subcommand per thing a person can ask for.
--
-- This surface exists BEFORE any model does, deliberately. Phases 1 through 6
-- are hands and levers, and the test of whether the levers were designed
-- properly is that pulling them by hand is satisfying. If the asking half is
-- never built, everything here still works.
--
-- Reached through scripts/neuron.
--------------------------------------------------------------------------------

local neuron_root = ...
if not neuron_root then
    io.stderr:write("020-cli: needs the neuron project root as its first argument\n")
    os.exit(2)
end

local arguments = { select(2, ...) }

local Deployment = dofile(neuron_root .. "/src/000-deployment.lua")
local Liveness   = dofile(neuron_root .. "/src/004-liveness.lua")
local WorldRead  = dofile(neuron_root .. "/src/005-world-read.lua")
local Receipts   = dofile(neuron_root .. "/src/006-receipts.lua")
local PlaceBook  = dofile(neuron_root .. "/src/011-place-book.lua")
local Rosters    = dofile(neuron_root .. "/src/012-rosters.lua")
local Teleport   = dofile(neuron_root .. "/src/013-teleport.lua")
local Return     = dofile(neuron_root .. "/src/014-return.lua")

-- {{{ parse_flags(arguments)
-- Turn `--key value` and `--flag` into a table.
--
-- A bare `--flag` becomes true; `--key value` becomes the string. Anything not
-- preceded by a flag is positional. Deliberately small -- this is an argument
-- reader, not an options framework, and every operation's real parameter
-- checking happens against its declaration rather than here.
local function parse_flags(list)
    local flags, positional = {}, {}
    local index = 1
    while index <= #list do
        local item = list[index]
        local key = item:match("^%-%-(.+)$")
        if key then
            local following = list[index + 1]
            if following and not following:match("^%-%-") then
                flags[key] = following
                index = index + 2
            else
                flags[key] = true
                index = index + 1
            end
        else
            table.insert(positional, item)
            index = index + 1
        end
    end
    return flags, positional
end
-- }}}

-- {{{ fail(message)
local function fail(message)
    io.stderr:write(message .. "\n")
    os.exit(1)
end
-- }}}

-- {{{ command_places(handle, flags, positional)
-- Find a place by name fragment.
local function command_places(handle, flags, positional)
    local fragment = positional[1] or ""
    local limit = tonumber(flags.limit) or 30

    local found, why = PlaceBook.search(handle, fragment, limit)
    if not found then fail(why) end

    if #found == 0 then
        print("no place matches '" .. fragment .. "'")
        return
    end

    for _, place in ipairs(found) do
        print("  " .. PlaceBook.describe(place))
    end
    print("")
    print(string.format("%d shown%s", #found,
        #found == limit and " (limited; pass --limit to see more)" or ""))
end
-- }}}

-- {{{ command_who(handle, flags, positional)
-- Resolve a roster and show it, without doing anything to it.
--
-- The point of this command is to be run BEFORE a command that changes things.
-- Seeing who a roster resolves to is how somebody avoids moving the wrong forty.
local function command_who(handle, flags, positional)
    local specification = positional[1] or flags.roster
    if not specification then
        fail("who: needs a roster.\n"
          .. "  neuron who 'bots hunters 18-20'\n"
          .. "  neuron who Grast,Wenna")
    end

    local resolution, why = Rosters.resolve(handle, specification,
        { limit = tonumber(flags.limit) })
    if not resolution then fail(why) end

    print(Rosters.describe(resolution))
    print("")
    for _, character in ipairs(resolution.characters) do
        print("  " .. WorldRead.describe_character(character))
    end
end
-- }}}

-- {{{ command_teleport(handle, flags, positional)
-- Plan a move, and unless --plan was given, apply it.
--
-- The two paths differ in exactly one thing: whether apply runs. There is no
-- separate simulation code, so the dry run cannot drift away from what really
-- happens -- it IS what really happens, stopped one step early.
local function command_teleport(handle, flags, positional)
    local roster = flags.roster or positional[1]
    local place  = flags.place  or positional[2]

    if not roster or not place then
        fail("teleport: needs a roster and a place.\n"
          .. "  neuron teleport --roster 'bots hunters 18-20' --place ratchet --plan\n"
          .. "  neuron teleport Grast ratchet")
    end

    local state = Liveness.probe(handle)

    local fault = Liveness.fault(state)
    if fault then fail(fault) end

    local hand, hand_why = Liveness.choose_hand(state, Teleport.declaration.hands)
    if not hand then fail(hand_why) end

    local plan, why = Teleport.plan(handle, {
        roster = roster,
        place  = place,
        limit  = tonumber(flags.limit),
        include_orphans = flags["include-orphans"] and true or nil,
    })
    if not plan then fail(why) end

    print(Teleport.describe_plan(plan))
    print("")

    if flags.plan then
        print("(--plan given; nothing was changed)")
        return
    end

    local receipt = Teleport.apply(handle, plan, state)

    print(Receipts.describe(receipt))

    if receipt.receipt_write_failed then
        io.stderr:write("\nWARNING: the world was changed but the receipt could not "
            .. "be written:\n  " .. receipt.receipt_write_failed .. "\n"
            .. "  Nothing can be undone without it.\n")
        os.exit(1)
    end

    -- A partial outcome is an exit code, not just a word in the output. Anything
    -- driving this from a script must be able to tell that the world is now
    -- half-changed without parsing prose.
    if receipt.outcome ~= "complete" then
        os.exit(1)
    end
end
-- }}}

-- {{{ command_return(handle, flags, positional)
-- Put characters back where a receipt says they were.
--
-- Goes through the same plan/apply path as everything else, so it can be
-- dry-run first and so undoing writes a receipt that can itself be undone.
local function command_return(handle, flags, positional)
    local id = flags.receipt or positional[1]
    if not id then
        fail("return: needs a receipt id.\n"
          .. "  neuron receipts                        to find one\n"
          .. "  neuron return --receipt <id> --plan")
    end

    local state = Liveness.probe(handle)

    local fault = Liveness.fault(state)
    if fault then fail(fault) end

    local hand, hand_why = Liveness.choose_hand(state, Return.declaration.hands)
    if not hand then fail(hand_why) end

    local plan, why = Return.plan(handle, { receipt = id })
    if not plan then fail(why) end

    print(Return.describe_plan(plan))
    print("")

    if flags.plan then
        print("(--plan given; nothing was changed)")
        return
    end

    local receipt = Return.apply(handle, plan, state)
    print(Receipts.describe(receipt))

    if receipt.outcome ~= "complete" then
        os.exit(1)
    end
end
-- }}}

-- {{{ command_receipts(handle, flags, positional)
-- Show what was done.
local function command_receipts(handle, flags, positional)
    local found, unreadable = Receipts.read(handle, {
        operation = flags.operation,
        date      = flags.date,
    })

    if unreadable > 0 then
        io.stderr:write(string.format(
            "WARNING: %d receipt line(s) could not be parsed and were skipped.\n"
         .. "  A process killed mid-write leaves a truncated final line.\n", unreadable))
    end

    if #found == 0 then
        print("no receipts for " .. (flags.date or os.date("%Y-%m-%d")))
        return
    end

    for _, receipt in ipairs(found) do
        print(Receipts.describe(receipt))
        print("")
    end
end
-- }}}

-- {{{ COMMANDS
-- A dispatch table, not a chain of comparisons: looking up a subcommand should
-- be one index, and a table is a thing that can be printed as help.
local COMMANDS = {
    places   = { fn = command_places,
                 usage = "neuron places [fragment] [--limit N]",
                 summary = "find named locations to teleport to" },
    who      = { fn = command_who,
                 usage = "neuron who <roster> [--limit N]",
                 summary = "resolve a roster and show who is in it" },
    teleport = { fn = command_teleport,
                 usage = "neuron teleport --roster <roster> --place <place> [--plan]",
                 summary = "move a roster to a place" },
    ["return"] = { fn = command_return,
                 usage = "neuron return --receipt <id> [--plan]",
                 summary = "put characters back, from a receipt" },
    receipts = { fn = command_receipts,
                 usage = "neuron receipts [--date YYYY-MM-DD] [--operation NAME]",
                 summary = "show what was done" },
}
-- }}}

-- {{{ usage()
local function usage()
    print("neuron -- a hand that reaches into a running world")
    print("")
    print("commands:")

    local names = {}
    for name in pairs(COMMANDS) do table.insert(names, name) end
    table.sort(names)

    for _, name in ipairs(names) do
        print(string.format("  %-10s %s", name, COMMANDS[name].summary))
        print(string.format("  %-10s %s", "", COMMANDS[name].usage))
    end

    print("")
    print("  status is its own script: scripts/status")
    print("")
    print("every command that changes anything takes --plan, which computes and")
    print("prints exactly what would happen and then does none of it.")
end
-- }}}

-- {{{ main
local flags, positional = parse_flags(arguments)
local command_name = table.remove(positional, 1)

if not command_name or command_name == "help" or flags.help then
    usage()
    os.exit(0)
end

local command = COMMANDS[command_name]
if not command then
    io.stderr:write("no such command: " .. command_name .. "\n\n")
    usage()
    os.exit(2)
end

local ok, handle = pcall(Deployment.load)
if not ok then
    fail("Cannot resolve which world to talk to:\n\n" .. tostring(handle))
end

command.fn(handle, flags, positional)
-- }}}
