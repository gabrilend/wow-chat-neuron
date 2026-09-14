--------------------------------------------------------------------------------
-- 065-secret-levers.lua
--
-- Credentials, as a thing that can be checked and replaced but never read.
--
-- The source levers (064) refuse secrets/, logs/ and tmp/ outright, and that is
-- right FOR READING. But a configuration assistant needs those directories --
-- it is the thing you open when a key is missing, wrong, or has the wrong
-- permissions, and it cannot help with any of that if it cannot tell whether a
-- file is there.
--
-- So the capability is split, and the split is the whole design:
--
--   READ      never. Not for any file under secrets/, not by any lever, not
--             through any argument. A model that has read a key has put it in
--             a conversation, in an asking log, and possibly on somebody
--             else's server.
--   EXISTS    yes. Present or absent, its permissions, how many characters --
--             everything needed to diagnose, none of it the secret.
--   WRITE     yes, through plan-and-confirm like any other change. Somebody
--             reads what is about to be written before it is.
--   REMOVE    yes.
--
-- A length is not a secret. Knowing an api.key holds 108 characters tells you
-- it is probably a real key rather than the word "placeholder", and tells you
-- nothing about what it is.
--------------------------------------------------------------------------------

local Secrets = {}

-- {{{ sibling / known keys
local function sibling(neuron_root, filename)
    return dofile(neuron_root .. "/src/" .. filename)
end

-- The credentials this knows about, by name. A closed set rather than a
-- directory scan: a scan would offer to overwrite anything somebody happened to
-- put in that folder, and the folder is where people put things they care about.
local function known(handle)
    return {
        ["soap.key"] = { path = handle.soap_key_path,
            what = "the game master account's password, for sending commands "
                .. "to a running world" },
        ["api.key"]  = { path = handle.api_key_path,
            what = "the key for the remote inference service" },
    }
end
-- }}}

-- {{{ Secrets.Status
Secrets.Status = {}

Secrets.Status.declaration = {
    name    = "secret.status",
    summary = "Report which credentials exist, their permissions and their "
           .. "length. Never their contents -- nothing here can read a "
           .. "credential.",
    kind    = "read",
    hands   = { "none" },
    params  = {},
}

function Secrets.Status.run(handle, args)
    local lines = {}

    for name, entry in pairs(known(handle)) do
        local file = io.open(entry.path, "r")

        if not file then
            table.insert(lines, string.format("%-10s ABSENT     %s",
                name, entry.what))
        else
            local contents = file:read("*a") or ""
            file:close()

            local mode = io.popen("stat -c '%a' '" .. entry.path .. "' 2>/dev/null")
            local permissions = mode and (mode:read("*l") or "?") or "?"
            if mode then mode:close() end

            local trimmed = contents:gsub("%s+$", "")

            table.insert(lines, string.format(
                "%-10s present    mode %s, %d characters%s",
                name, permissions, #trimmed,
                permissions ~= "600" and "   -- SHOULD BE 600" or ""))
        end
    end

    table.sort(lines)

    return { describes = table.concat(lines, "\n")
        .. "\n\nNothing here can read a credential. Length and permissions "
        .. "are enough to say whether one is plausible; the contents are not "
        .. "reachable from this conversation at all." }
end
-- }}}

-- {{{ Secrets.Write
Secrets.Write = {}

Secrets.Write.declaration = {
    name    = "secret.write",
    summary = "Replace a credential. The value is written and never read back "
           .. "-- ask the person for it, put it here, and confirm what it "
           .. "replaced only by its length.",
    kind    = "change",
    hands   = { "none" },
    params  = {
        { name = "name", type = "string", required = true,
          describes = "Which credential: soap.key or api.key." },
        { name = "value", type = "string", required = true,
          describes = "The credential itself, alone -- no name, no equals sign, "
                   .. "no quotes. If the person gave you a whole config line, "
                   .. "send only the part after the equals sign." },
    },
}

function Secrets.Write.plan(handle, args)
    local name  = tostring(args.name or "")
    local entry = known(handle)[name]

    if not entry then
        local names = {}
        for key in pairs(known(handle)) do table.insert(names, key) end
        table.sort(names)
        return nil, string.format("There is no credential called '%s'. "
            .. "This knows: %s.", name, table.concat(names, ", "))
    end

    local value = tostring(args.value or ""):gsub("^%s+", ""):gsub("%s+$", "")

    if value == "" then
        return nil, "Nothing to write."
    end

    if value:find("=") then
        return nil, "That contains an equals sign, so it is probably a whole "
                 .. "config line rather than the secret. Send only the part "
                 .. "after the equals sign."
    end

    local existing = io.open(entry.path, "r")
    local was = nil
    if existing then
        was = #((existing:read("*a") or ""):gsub("%s+$", ""))
        existing:close()
    end

    return {
        operation = "secret.write",
        name      = name,
        path      = entry.path,
        value     = value,
        was       = was,
        steps = { { describes = string.format("write %d characters to %s",
            #value, name) } },
    }
end

function Secrets.Write.describe_plan(plan)
    -- The plan says the LENGTH, never the value. A plan is shown on screen and
    -- written into the asking log; putting the credential in it would put it in
    -- both.
    return string.format(
        "replace %s\n\n  %s\n  %s -> %d characters\n\n"
     .. "Created empty, narrowed to mode 600, then filled -- in that order, so "
     .. "it is never briefly readable by anyone else.",
        plan.name, plan.path,
        plan.was and (plan.was .. " characters") or "absent", #plan.value)
end

function Secrets.Write.apply(handle, plan, state)
    local directory = plan.path:match("^(.*)/[^/]*$")
    os.execute(string.format("mkdir -p '%s' && chmod 700 '%s'",
        directory, directory))
    os.execute(string.format("touch '%s' && chmod 600 '%s'",
        plan.path, plan.path))

    local file = io.open(plan.path, "w")
    local ok = false

    if file then
        file:write(plan.value)
        file:close()
        os.execute(string.format("chmod 600 '%s'", plan.path))
        ok = true
    end

    local receipt = {
        operation = "secret.write",
        -- The value is NOT in the arguments. A receipt is append-only and kept;
        -- a credential in one is a credential kept forever.
        arguments = { name = plan.name, characters = #plan.value },
        started   = os.time(), finished = os.time(),
        steps = { { describes = plan.steps[1].describes, hand = "none",
                    outcome = ok and "done" or "failed",
                    detail = ok and "mode 600" or "could not write" } },
        outcome = ok and "complete" or "refused",
    }

    sibling(handle.neuron_root, "006-receipts.lua").write(handle, receipt)
    return receipt
end
-- }}}

-- {{{ Secrets.Clear
Secrets.Clear = {}

Secrets.Clear.declaration = {
    name    = "secret.clear",
    summary = "Remove a credential. What it was for then falls back to whatever "
           .. "happens without it.",
    kind    = "change",
    hands   = { "none" },
    params  = {
        { name = "name", type = "string", required = true,
          describes = "Which credential: soap.key or api.key." },
    },
}

function Secrets.Clear.plan(handle, args)
    local name  = tostring(args.name or "")
    local entry = known(handle)[name]

    if not entry then
        return nil, string.format("There is no credential called '%s'.", name)
    end

    if not io.open(entry.path, "r") then
        return nil, name .. " is already gone."
    end

    return {
        operation = "secret.clear",
        name = name, path = entry.path,
        steps = { { describes = "remove " .. name } },
    }
end

function Secrets.Clear.describe_plan(plan)
    return string.format("remove %s\n\n  %s", plan.name, plan.path)
end

function Secrets.Clear.apply(handle, plan, state)
    local removed = os.remove(plan.path) and true or false

    local receipt = {
        operation = "secret.clear",
        arguments = { name = plan.name },
        started   = os.time(), finished = os.time(),
        steps = { { describes = plan.steps[1].describes, hand = "none",
                    outcome = removed and "done" or "failed" } },
        outcome = removed and "complete" or "refused",
    }

    sibling(handle.neuron_root, "006-receipts.lua").write(handle, receipt)
    return receipt
end
-- }}}

return Secrets
