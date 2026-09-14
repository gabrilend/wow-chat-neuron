--------------------------------------------------------------------------------
-- 064-source-levers.lua
--
-- Letting the local model read the project. All of it, and none of it writable.
--
-- The configuration window exists for the moment when something is wrong, and
-- what is wrong is very often in the code rather than in a setting. A model
-- that can read 049-spawn.lua can say "your place resolved to a dock and the
-- ground check refused it, look at line 130" instead of guessing. One that
-- cannot read anything can only guess.
--
-- READ ONLY, and not by convention -- there is no write function here to
-- disable. If a fix is wanted, the model describes it and a person types it.
-- That is the same position the whole project takes about the world: the model
-- pulls levers, it does not write code.
--
-- WHAT IS NOT READABLE, and why it is a list of what IS rather than a list of
-- what is not:
--
--   secrets/    credentials. A model that can read a key is a key in a
--               conversation, in an asking log, and possibly on somebody
--               else's server.
--   logs/       past conversations, which may quote credentials that were
--               pasted into a window.
--   tmp/        the RAM tier: request bodies, curl config files with the
--               credential in them, receipts.
--
-- Allow-listing the readable directories rather than blocking those three is
-- the difference between forgetting to add a rule and forgetting to add a
-- directory. The first leaks; the second merely fails to show something.
--------------------------------------------------------------------------------

local Source = {}

-- {{{ READABLE
-- The directories a model may read, by name, from the project root.
local READABLE = {
    "src", "docs", "issues", "config", "scripts", "tests", "assets", "notes",
}

-- Files whose extensions are worth reading. A model asking for a binary gets a
-- refusal rather than several megabytes of nothing.
local READABLE_KINDS = {
    lua = true, md = true, txt = true, html = true, sh = true,
    json = true, conf = true, css = true, js = true,
}
-- }}}

-- {{{ within_project(handle, path)
-- Is this a file the model may read?
--
-- The check is on the RESOLVED path, after `..` has been collapsed, because a
-- path is not what it looks like until it has been. `src/../secrets/api.key`
-- looks like it is under src and is not.
local function within_project(handle, path)
    local Load = dofile(handle.neuron_root .. "/src/024-load.lua")

    -- normalise lives in the loader; reuse it rather than writing a second one
    -- that collapses `..` slightly differently.
    local full = path
    if full:sub(1, 1) ~= "/" then
        full = handle.neuron_root .. "/" .. full
    end

    local pieces = {}
    for piece in full:gmatch("[^/]+") do
        if piece == ".." then
            if #pieces > 0 then table.remove(pieces) end
        elseif piece ~= "." then
            table.insert(pieces, piece)
        end
    end
    full = "/" .. table.concat(pieces, "/")

    local root = handle.neuron_root
    if full:sub(1, #root + 1) ~= root .. "/" then
        return nil, string.format(
            "%s is outside the project. Only files inside %s can be read.",
            path, root)
    end

    local relative = full:sub(#root + 2)
    local directory = relative:match("^([^/]+)")

    for _, allowed in ipairs(READABLE) do
        if directory == allowed then
            local extension = relative:match("%.([%w]+)$")
            if extension and not READABLE_KINDS[extension:lower()] then
                return nil, string.format(
                    "%s is a .%s file, which is not one of the kinds worth "
                 .. "reading here (lua, md, txt, html, sh, json, conf, css, js).",
                    relative, extension)
            end
            return full, relative
        end
    end

    return nil, string.format(
        "%s is not in a readable part of the project.\n"
     .. "  Readable: %s.\n"
     .. "  Deliberately not readable: secrets (credentials), logs (past "
     .. "conversations, which may quote a credential somebody pasted in), and "
     .. "tmp (request bodies and option files that hold credentials while they "
     .. "are in use).", path, table.concat(READABLE, ", "))
end
-- }}}

-- {{{ Source.List
Source.List = {}

Source.List.declaration = {
    name    = "source.list",
    summary = "List the project's source files, optionally filtered by a "
           .. "fragment of the path. Use this to find out what exists before "
           .. "reading anything.",
    kind    = "read",
    hands   = { "none" },
    params  = {
        { name = "matching", type = "string", required = false,
          describes = "Part of a path, such as 'spawn' or 'src/025-enums'. "
                   .. "Leave it out to list everything." },
    },
}

function Source.List.run(handle, args)
    local wanted = tostring(args.matching or ""):lower()

    local directories = {}
    for _, name in ipairs(READABLE) do
        table.insert(directories, "'" .. handle.neuron_root .. "/" .. name .. "'")
    end

    local pipe = io.popen(string.format(
        "find %s -type f 2>/dev/null | sort", table.concat(directories, " ")), "r")

    if not pipe then
        return nil, "cannot list the project directory."
    end

    local found = {}
    for path in pipe:lines() do
        local relative = path:sub(#handle.neuron_root + 2)
        local extension = relative:match("%.([%w]+)$")

        if (not extension or READABLE_KINDS[extension:lower()])
        and (wanted == "" or relative:lower():find(wanted, 1, true)) then
            table.insert(found, relative)
        end
    end
    pipe:close()

    if #found == 0 then
        return { describes = string.format(
            "Nothing matches '%s'. The readable directories are: %s.",
            args.matching or "", table.concat(READABLE, ", ")) }
    end

    -- All of them. A truncated listing is a listing you cannot trust to be
    -- complete, and "narrow it with matching" asks somebody to guess at a name
    -- they opened the listing to find.
    local lines = {}
    for _, path in ipairs(found) do table.insert(lines, "  " .. path) end

    return { describes = string.format("%d file%s%s:\n%s",
        #found, #found == 1 and "" or "s",
        wanted ~= "" and (" matching '" .. args.matching .. "'") or "",
        table.concat(lines, "\n")) }
end
-- }}}

-- {{{ Source.Read
Source.Read = {}

Source.Read.declaration = {
    name    = "source.read",
    summary = "Read one of the project's source files. Read only -- nothing "
           .. "here can change a file. Describe a fix and a person will type it.",
    kind    = "read",
    hands   = { "none" },
    params  = {
        { name = "path", type = "string", required = true,
          describes = "The path from the project root, as source.list gives it "
                   .. "-- for example 'src/049-spawn.lua'." },
        { name = "from", type = "integer", required = false,
          describes = "First line to return. Leave it out to start at the top." },
        { name = "lines", type = "integer", required = false, default = 200,
          describes = "How many lines. Files here run to five hundred lines and "
                   .. "reading a whole one costs most of a small model's memory." },
    },
}

function Source.Read.run(handle, args)
    local full, relative = within_project(handle, tostring(args.path or ""))
    if not full then return nil, relative end

    local file = io.open(full, "r")
    if not file then
        return nil, string.format(
            "%s is readable in principle and is not there. `source.list` says "
         .. "what exists.", relative)
    end

    local from  = math.max(1, math.floor(tonumber(args.from) or 1))
    local count = math.min(600, math.max(1, math.floor(tonumber(args.lines) or 200)))

    local lines, number = {}, 0
    for line in file:lines() do
        number = number + 1
        if number >= from and #lines < count then
            table.insert(lines, string.format("%5d  %s", number, line))
        end
    end
    file:close()

    if #lines == 0 then
        return { describes = string.format(
            "%s has %d lines; there is nothing at line %d.", relative, number, from) }
    end

    local last = from + #lines - 1

    return { describes = string.format("%s, lines %d-%d of %d:\n\n%s%s",
        relative, from, last, number, table.concat(lines, "\n"),
        last < number and string.format(
            "\n\n(%d more lines; ask again with from=%d)", number - last, last + 1)
        or "") }
end
-- }}}

return Source
