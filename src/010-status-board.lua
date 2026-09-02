--------------------------------------------------------------------------------
-- 010-status-board.lua
--
-- The observable half of phase 1: point neuron at a world and have it say what
-- it can see and what it may therefore do.
--
-- Nothing here changes anything. It is entirely reads and probes, which is why
-- it is safe to run at any time and is the right first move when something is
-- not working.
--
-- Reached through scripts/status.
--------------------------------------------------------------------------------

local neuron_root = ...
if not neuron_root then
    io.stderr:write("010-status-board: needs the neuron project root as its argument\n")
    os.exit(2)
end

local Deployment = dofile(neuron_root .. "/src/000-deployment.lua")
local Liveness   = dofile(neuron_root .. "/src/004-liveness.lua")
local WorldRead  = dofile(neuron_root .. "/src/005-world-read.lua")

-- {{{ rule(title)
local function rule(title)
    print("")
    print("== " .. title .. " " .. string.rep("=", math.max(0, 60 - #title)))
    print("")
end
-- }}}

-- {{{ main
local ok, handle = pcall(Deployment.load)
if not ok then
    io.stderr:write("Cannot resolve which world to talk to:\n\n" .. tostring(handle) .. "\n")
    os.exit(1)
end

rule("pointing at")
print(Deployment.describe(handle))

rule("what is running")
local state = Liveness.probe(handle)

-- The impossible combination is checked BEFORE anything is reported as normal.
-- Proceeding past a fault would mean reporting confidently about a world other
-- than the one being changed, which is worse than reporting nothing.
local fault = Liveness.fault(state)
if fault then
    print(fault)
    os.exit(1)
end

print(Liveness.describe(state))

-- Everything below needs the database. With it down there is nothing further to
-- say, and saying so plainly beats printing a page of zeroes that look like
-- facts about an empty world.
if not state.db_up then
    rule("the world")
    print("Nothing further can be read while the database is down.")
    print("")
    os.exit(0)
end

rule("the world")
local summary, why = WorldRead.summary(handle)
if not summary then
    print("Could not read a summary: " .. tostring(why))
    os.exit(1)
end

print(string.format("characters   %d", summary.characters))
print(string.format("accounts     %d", summary.accounts))
print(string.format("parties      %d", summary.parties))
print(string.format("online now   %d", summary.online))

if summary.online > 0 then
    rule("who is playing")
    local online = WorldRead.characters_online(handle)
    if online then
        for _, character in ipairs(online) do
            print("  " .. WorldRead.describe_character(character))
        end
    end
end

print("")
-- }}}
