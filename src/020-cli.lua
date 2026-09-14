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
local Retire     = dofile(neuron_root .. "/src/015-retire.lua")
local Dangling   = dofile(neuron_root .. "/src/016-dangling.lua")

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

-- {{{ command_retire(handle, flags, positional)
-- Remove characters and everything referring to them.
--
-- The only command here that cannot be undone, so it asks twice: --plan shows
-- what would go, and applying requires --yes-remove-them spelled out. A single
-- character flag is too easy to type by accident for something with no reverse.
local function command_retire(handle, flags, positional)
    local roster = flags.roster or positional[1]
    if not roster then
        fail("retire: needs a roster.\n"
          .. "  neuron retire --roster orphans --plan\n"
          .. "  neuron retire --roster orphans --yes-remove-them")
    end

    local state = Liveness.probe(handle)

    local fault = Liveness.fault(state)
    if fault then fail(fault) end

    -- Refused outright while a worldserver is up. Removing rows out from under a
    -- running game leaves it holding objects whose rows are gone, and the
    -- failure mode is a crash at some later, unrelated moment.
    if state.world_up then
        fail("retire: the worldserver is running.\n"
          .. "  Removing characters out from under a live server leaves it holding\n"
          .. "  objects whose rows no longer exist, and it will fail later at some\n"
          .. "  unrelated moment. Stop the worldserver first.")
    end

    local hand, hand_why = Liveness.choose_hand(state, Retire.declaration.hands)
    if not hand then fail(hand_why) end

    local plan, why = Retire.plan(handle, {
        roster  = roster,
        confirm = flags.confirm and true or nil,
        include_orphans = true,
    })
    if not plan then fail(why) end

    print(Retire.describe_plan(plan))
    print("")

    if flags.plan or not flags["yes-remove-them"] then
        if flags.plan then
            print("(--plan given; nothing was changed)")
        else
            print("(nothing was changed -- pass --yes-remove-them to actually do this)")
        end
        return
    end

    local receipt = Retire.apply(handle, plan, state)
    print(Receipts.describe(receipt))

    if receipt.backup then
        print("")
        print("backup: " .. receipt.backup)
        print("        That path is in RAM and will NOT survive a reboot. Copy it")
        print("        somewhere durable if you want to keep it.")
    end

    if receipt.outcome ~= "complete" then
        os.exit(1)
    end
end
-- }}}

-- {{{ command_check(handle, flags, positional)
-- Look for rows that name a character who does not exist.
--
-- The proof that a removal was complete, and the alarm that says a future one
-- was not. Reads only.
local function command_check(handle, flags, positional)
    local result, why = Dangling.check(handle)
    if not result then fail(why) end

    print(Dangling.describe(result))

    -- Residue is a finding, not a statistic. Per the standing position that a
    -- warning is an error, a non-zero result exits non-zero so anything running
    -- this in a build or a hook notices.
    if result.total > 0 then
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

-- {{{ command_atoms(handle, flags, positional)
-- The pieces a conversation is made of, and what has been done to each.
--
-- An atom is a run of blocks between two signposts in the split transcript --
-- however much sits there, because a signpost points a direction and says
-- nothing about size. This is the only place they can be seen, and seeing them
-- is the whole prerequisite for deciding what to cut.
--
--     neuron atoms 2026-09-06/013000-beef
--     neuron atoms <id> --drop 4 --why "the table is huge"
--     neuron atoms <id> --fold 4,5 --says "looked it up twice" --why "budget"
--     neuron atoms <id> --keep 4
--
-- Nothing here rewrites a transcript. Every edit is one more line in an
-- append-only log beside it, and reading replays that log from the start -- so
-- what a conversation WAS is never up for revision, only what gets sent.
local function command_atoms(handle, flags, positional)
    local Transcript = dofile(handle.neuron_root .. "/src/067-transcript.lua")

    local id = positional[1]
    if not id then
        fail("which conversation? Their ids are the date and time, as\n"
          .. "  scripts/neuron receipts prints them and as the menu lists\n"
          .. "  them -- for example 2026-09-06/013000-beef.")
    end

    -- {{{ numbers_in(text)
    local function numbers_in(text)
        local found = {}
        for number in tostring(text or ""):gmatch("%d+") do
            table.insert(found, tonumber(number))
        end
        return found
    end
    -- }}}

    local why = flags.why or "from the command line"

    for _, verb in ipairs({ "drop", "keep", "fold" }) do
        if flags[verb] then
            local ok, trouble = Transcript.prune(handle, id, verb,
                numbers_in(flags[verb]), flags.says, why)
            if not ok then fail(trouble) end
            print(string.format("%s %s  (%s)", verb, flags[verb], why))
            print("")
        end
    end

    local atoms = Transcript.atoms(handle, id)

    if #atoms == 0 then
        fail("no conversation at " .. id .. ", or it has nothing in it yet.")
    end

    print(string.format("%-5s %-8s %6s %8s  %s",
        "atom", "state", "blocks", "chars", "what is in it"))

    local kept_characters, cut_characters = 0, 0

    for _, atom in ipairs(atoms) do
        print(string.format("%-5d %-8s %6d %8d  %s",
            atom.section, atom.state, atom.blocks, atom.characters,
            atom.says or table.concat(atom.markers, ",")))

        if atom.state == "kept" then
            kept_characters = kept_characters + atom.characters
        else
            cut_characters = cut_characters + atom.characters
        end
    end

    print("")
    print(string.format("%d characters kept, %d cut",
        kept_characters, cut_characters))

    -- Said rather than assumed: the count above is characters, and what a model
    -- charges for is tokens. Four characters to a token is the usual rule of
    -- thumb for English and it is a rule of thumb, not a measurement.
    print(string.format("roughly %d tokens, at four characters each -- a rule "
        .. "of thumb, not a count", math.floor(kept_characters / 4)))
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
    check    = { fn = command_check,
                 usage = "neuron check",
                 summary = "find rows naming characters that no longer exist" },
    retire   = { fn = command_retire,
                 usage = "neuron retire --roster <roster> [--plan | --yes-remove-them]",
                 summary = "remove characters completely -- CANNOT be undone" },
    receipts = { fn = command_receipts,
                 usage = "neuron receipts [--date YYYY-MM-DD] [--operation NAME]",
                 summary = "show what was done" },
    atoms    = { fn = command_atoms,
                 usage = "neuron atoms <id> [--drop N | --keep N | --fold N,M --says TEXT] [--why TEXT]",
                 summary = "the pieces a conversation is made of, and cut some out" },
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

local ok, handle = pcall(Deployment.load)
if not ok then
    fail("Cannot resolve which world to talk to:\n\n" .. tostring(handle))
end

if command then
    command.fn(handle, flags, positional)
    os.exit(0)
end

-- {{{ the registry, for anything the hand-written commands do not cover
-- Every word in the registry, reachable by its verb, without a subcommand
-- having been written for it.
--
-- The seven above are older than the registry and still work the way they
-- always did (issue 702 replaces them). This is the path everything NEW
-- arrives on -- so a word that is declared is a word that can be pulled the
-- moment it exists, rather than when somebody remembers to add a function
-- here.
local Registry = dofile(neuron_root .. "/src/045-toolbox/047-registry.lua")

local registry, registry_why = Registry.load(neuron_root)
if not registry then
    fail("The vocabulary would not load:\n" .. registry_why)
end

local operation
for _, candidate in ipairs(registry.ordered) do
    if candidate.verb == command_name or candidate.name == command_name then
        operation = candidate
    end
end

if not operation then
    io.stderr:write("no such command: " .. command_name .. "\n\n")
    usage()
    io.stderr:write("\nand from the registry:\n")
    for _, word in ipairs(registry.ordered) do
        io.stderr:write(string.format("  %-10s %s\n    %s\n",
            word.verb, word.summary, Registry.usage(word)))
    end
    os.exit(2)
end

-- Arguments come off the flags, coerced only as far as the declared type. The
-- full coercion layer is issue 704; this handles the four plain types and
-- leaves the resolving ones as the strings each operation already resolves
-- itself.
local arguments = {}
for _, parameter in ipairs(operation.params) do
    local given = flags[parameter.name]

    if given ~= nil then
        if parameter.type.name == "integer" then
            arguments[parameter.name] = math.floor(tonumber(given) or 0)
        elseif parameter.type.name == "number" then
            arguments[parameter.name] = tonumber(given)
        elseif parameter.type.name == "boolean" then
            arguments[parameter.name] = (given == true or given == "true"
                or given == "yes" or given == "1")
        else
            arguments[parameter.name] = given
        end
    elseif parameter.required then
        fail(string.format("%s needs --%s\n  %s\n\n  %s",
            operation.name, parameter.name, parameter.describes,
            Registry.usage(operation)))
    end
end

if operation.kind.name == "read" then
    local answer, why = operation.run(handle, arguments)
    if not answer then fail(why) end
    print(answer.describes or "done")
    os.exit(0)
end

local plan, plan_why = operation.plan(handle, arguments)
if not plan then fail(plan_why) end

print(operation.describe_plan and operation.describe_plan(plan)
    or (#(plan.steps or {}) .. " steps"))

if flags.plan then
    print("")
    print("(--plan given; nothing was changed)")
    os.exit(0)
end

-- Anything that cannot be undone needs saying yes to, in the same breath.
if operation.kind.name == "final" and not flags.confirm then
    print("")
    fail("This cannot be undone. Pass --confirm to mean it.")
end

local Liveness = dofile(neuron_root .. "/src/004-liveness.lua")
local state = Liveness.probe(handle)

local receipt = operation.apply(handle, plan, state)

print("")
print(Receipts.describe(receipt))

if receipt.outcome ~= "complete" then os.exit(1) end
-- }}}
-- }}}
