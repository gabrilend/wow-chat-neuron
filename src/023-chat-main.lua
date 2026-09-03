--------------------------------------------------------------------------------
-- 023-chat-main.lua
--
-- Starts the chat window's server. Reached through scripts/neuron-chat.
--------------------------------------------------------------------------------

local neuron_root, port, wanted_profile = ...

-- An empty string arrives when the shell passes an unset variable; treat it as
-- absent rather than as a profile named "".
if wanted_profile == "" then wanted_profile = nil end

if not neuron_root then
    io.stderr:write("023-chat-main: needs the neuron project root as its argument\n")
    os.exit(2)
end

local Deployment = dofile(neuron_root .. "/src/000-deployment.lua")
local HttpServer = dofile(neuron_root .. "/src/022-http-server.lua")

-- {{{ main
local ok, handle = pcall(Deployment.load, wanted_profile)
if not ok then
    io.stderr:write("Cannot resolve which world to talk to:\n\n" .. tostring(handle) .. "\n")
    os.exit(1)
end

print("")
print(Deployment.describe(handle))
print("")

local server = HttpServer.new(handle, { port = tonumber(port) })

local ran, why = HttpServer.run(server)
if not ran then
    io.stderr:write(tostring(why) .. "\n")
    os.exit(1)
end
-- }}}
