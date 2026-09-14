--------------------------------------------------------------------------------
-- 055-list-stubs.lua
--
-- Print every placeholder declared anywhere in the project.
--
-- Works by LOADING the source and asking, rather than by searching it for a
-- comment convention. The difference matters: a grep for "TODO" finds what
-- somebody wrote about the code, and this finds what the code actually declares
-- about itself. The second cannot disagree with the first because there is no
-- first.
--
-- Reached through scripts/stubs.
--------------------------------------------------------------------------------

local neuron_root = ...

if not neuron_root then
    io.stderr:write("055-list-stubs: needs the project root as its argument\n")
    os.exit(2)
end

local Load  = dofile(neuron_root .. "/src/024-load.lua")
local Stubs = Load(neuron_root .. "/src/054-stubs.lua")

-- {{{ is_entry_point(path)
-- Does this file expect to be RUN rather than required?
--
-- Entry points in this project open by taking the project root out of `...`
-- and exiting if it is absent -- 010-status-board, 020-cli, 059-menu and
-- this file all do. Loading one with no arguments calls os.exit, which pcall
-- does not catch and which therefore kills the listing rather than being
-- skipped.
--
-- Detected by the convention rather than by a hand-kept list, so a new entry
-- point does not have to be remembered here. The convention is `local <name> =
-- ...` in the opening lines, which is exactly what marks a file as taking
-- arguments.
local function is_entry_point(path)
    local file = io.open(path, "r")
    if not file then return false end

    local opening = file:read(3000) or ""
    file:close()

    -- A comma-separated name list too: a window opens with three names,
    -- and matching only a single one skipped it, let it load, and let it exit
    -- out from under the listing.
    return opening:find("\nlocal [%w_, ]+ = %.%.%.") ~= nil
end
-- }}}

-- {{{ load_everything(root)
-- Every module under src/, so that every module-scope declaration has run.
--
-- Entry points are skipped rather than attempted -- see above. A module that
-- genuinely fails to load is reported and the listing carries on, because the
-- point is to see the stubs that ARE declarable rather than to prove the tree
-- is healthy.
local function load_everything(root)
    local listing = io.popen("find " .. ("'" .. root .. "/src'")
        .. " -name '*.lua' | sort", "r")

    if not listing then
        io.stderr:write("cannot list the source directory\n")
        os.exit(1)
    end

    local skipped, entry_points = {}, {}

    for path in listing:lines() do
        local short = path:gsub(".*/src/", "")

        if is_entry_point(path) then
            table.insert(entry_points, short)
        else
            local ok, why = pcall(Load, path)
            if not ok then
                table.insert(skipped, {
                    file = short,
                    why  = tostring(why):gsub("\n.*", ""),
                })
            end
        end
    end

    listing:close()
    return skipped, entry_points
end
-- }}}

local skipped, entry_points = load_everything(neuron_root)
local declared = Stubs.declared()

print("")

if #declared == 0 then
    print("No placeholders declared anywhere.")
    print("")
    print("That means either everything is finished, or nothing that stands in")
    print("for something else has said so. The second is much more likely --")
    print("see issues/109-standing-stubs.md for how a path declares itself.")
else
    print(string.format("%d placeholder%s:", #declared,
        #declared == 1 and "" or "s"))
    print("")

    for _, stub in ipairs(declared) do
        print(stub:describe())
        print("")
    end
end

if #entry_points > 0 then
    print(string.format("%d entry point%s skipped -- they take arguments and "
        .. "exit without them:", #entry_points, #entry_points == 1 and "" or "s"))
    print("  " .. table.concat(entry_points, "  "))
    print("")
end

if #skipped > 0 then
    print(string.format(
        "%d module%s would not load and were not searched:",
        #skipped, #skipped == 1 and "" or "s"))

    for _, entry in ipairs(skipped) do
        print(string.format("  %-38s %s", entry.file, entry.why))
    end
    print("")
end

print("")
