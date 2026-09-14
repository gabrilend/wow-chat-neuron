--------------------------------------------------------------------------------
-- 060-menu-main.lua
--
-- Start the menu. Reached through scripts/neuron-menu.
--------------------------------------------------------------------------------

local neuron_root, port, host = ...

if not neuron_root then
    io.stderr:write("060-menu-main: needs the neuron project root as its "
        .. "first argument\n")
    os.exit(2)
end

local Deployment = dofile(neuron_root .. "/src/000-deployment.lua")
local Menu       = dofile(neuron_root .. "/src/059-menu.lua")

-- The menu must load even when the deployment does not, because "which world"
-- being unanswerable is exactly the sort of thing somebody opens the menu to
-- find out about. So the failure is printed and the page is not served -- but
-- the message is the whole reason rather than a stack trace.
local ok, handle = pcall(Deployment.load)

if not ok then
    io.stderr:write("The menu cannot say which world this is:\n\n"
        .. tostring(handle) .. "\n")
    os.exit(1)
end

-- The address to bind, passed through from the launcher. Empty means the
-- launcher said nothing, which means loopback -- the argument arrives as "" and
-- not as nil when a shell script passes an unset variable.
if host == "" then host = nil end

Menu.run(Menu.new(handle, tonumber(port) or 7900, host))
