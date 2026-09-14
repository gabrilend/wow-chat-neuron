--------------------------------------------------------------------------------
-- 072-addons.lua
--
-- Which optional modules this deployment was built with.
--
-- AzerothCore's interesting parts are modules, and a module is either compiled
-- into the worldserver or it is not. Everything neuron can do through one --
-- spawning a creature that appears immediately, anything about playerbots --
-- simply does not exist on a server built without it.
--
-- WHY ASK AT ALL. A tool that cannot work is worse than a tool that is absent:
-- absent, a model composes around it; present and broken, it tries, gets a
-- failure it cannot interpret, and tries again. And a person reading the
-- library wants to know that the word is missing because of a build decision
-- rather than because they misremembered its name.
--
-- HOW IT IS ASKED. By the config file the module installs, in the profile's own
-- etc/modules directory. Not by looking in the source tree: source can be
-- present and unbuilt, and can be absent from a tree whose binary has the
-- module compiled in. The installed config is written by the module's own
-- install step, so it is the closest thing to evidence available without asking
-- the running server -- which is not available, because the whole point is to
-- answer while nothing is running.
--
-- It is EVIDENCE, not proof. Somebody who deletes a conf file has a server that
-- still has the module. That is a strange thing to do and the failure is
-- legible: the word is listed as missing and the operation would have worked.
--------------------------------------------------------------------------------

local Addons = {}

-- {{{ KNOWN
-- The modules neuron cares about, and what it loses without each.
--
-- A table rather than a chain of comparisons, and the `absent` text is written
-- here rather than at each use, so a word's explanation for being unavailable
-- is the same sentence wherever it is shown.
Addons.KNOWN = {
    {
        name  = "ale",
        title = "mod-ale",
        conf  = "mod_ale.conf",
        gives = "runs Lua inside the worldserver",
        absent = "mod-ale is not installed on this deployment. It is what lets "
              .. "neuron run a script inside the running worldserver, which is "
              .. "the only way to change something and have it appear without "
              .. "a restart.",
    },
    {
        name  = "playerbots",
        title = "mod-playerbots",
        conf  = "playerbots.conf",
        gives = "the fleet of AI characters",
        absent = "mod-playerbots is not installed on this deployment. There are "
              .. "no bots to act on, so anything about them has nothing to "
              .. "reach.",
    },
}
-- }}}

-- {{{ Addons.installed(handle)
-- A set of module names to true, and a list in declaration order.
--
-- Answered from disk every time rather than remembered. The profile can change
-- underneath this -- switching one points at an entirely different installed
-- tree -- and a cached answer would describe the tree neuron used to be looking
-- at.
function Addons.installed(handle)
    -- Beside the server's own configuration, wherever that turned out to be.
    -- Built from the profile and the root until the deployment could be any
    -- shape, which meant addon detection quietly answered "nothing installed"
    -- on every deployment that did not use profiles.
    local where = (handle.config_dir or "") .. "/modules"

    local present, listed = {}, {}

    for _, addon in ipairs(Addons.KNOWN) do
        local file = io.open(where .. "/" .. addon.conf, "r")
        local there = file ~= nil
        if file then file:close() end

        present[addon.name] = there

        -- An explicit if, not `there and nil or addon.absent`. In Lua that
        -- expression ALWAYS yields the right-hand side: `and nil` is falsy, so
        -- `or` takes over. Every installed module came back marked present and
        -- carrying a sentence saying it was not.
        local entry = { name = addon.name, title = addon.title,
                        gives = addon.gives, present = there }

        if not there then entry.why = addon.absent end

        table.insert(listed, entry)
    end

    return present, listed
end
-- }}}

-- {{{ Addons.why_missing(handle, needs)
-- The reason a word is unavailable, or nil when it is available.
--
-- `needs` is the list an operation declares. One sentence per missing module,
-- joined -- an operation that needs two and has neither should say both, since
-- installing one of them would not help.
function Addons.why_missing(handle, needs)
    if not needs or #needs == 0 then return nil end

    local present = Addons.installed(handle)
    local reasons = {}

    for _, wanted in ipairs(needs) do
        if not present[wanted] then
            for _, addon in ipairs(Addons.KNOWN) do
                if addon.name == wanted then
                    table.insert(reasons, addon.absent)
                end
            end
        end
    end

    if #reasons == 0 then return nil end
    return table.concat(reasons, "\n\n")
end
-- }}}

return Addons
