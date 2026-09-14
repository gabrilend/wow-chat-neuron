--------------------------------------------------------------------------------
-- 075-reading-order.lua
--
-- The index of the whole project, read back out of the project itself.
--
-- The reading order was a hand-kept table, and it went stale the way hand-kept
-- tables do: it stopped at 051 while the source ran to 074, it still listed
-- three files that had been replaced, and its last five rows had drifted out of
-- numeric order -- in a document whose entire claim is that numeric order IS
-- the order. A reader following it was being told the shape of a project that
-- no longer existed.
--
-- So it is generated. Every row here is taken from the file it describes: the
-- index off the front of the filename, the sentence out of the file's own
-- header. There is nothing to keep in step, because there is only one copy.
--
-- WHAT A HEADER LOOKS LIKE, and why the reading is anchored rather than
-- searched. Every source file in this project opens the same way:
--
--     line 1   a rule of dashes
--     line 2   -- <the file's own name>
--     line 3   --
--     line 4   -- the summary, which may wrap
--     line 5+  -- the rest of the header, after a blank comment line
--
-- The summary is taken from line 4 onward, up to the first blank comment line or
-- the closing rule, and then cut back to a sentence or two. Anchoring on line 4
-- rather than hunting for the first prose line means a file with a malformed
-- header fails visibly instead of quietly contributing somebody's aside.
--
-- If a summary reads badly in the table, the fix is to write a better opening
-- sentence in the file. That is an improvement to the file either way, and it
-- is the only place the sentence lives.
--
-- WHAT IS NOT GENERATED. The prose around the table -- what the numbering
-- means, what is reserved, how tests are named -- is writing, not extraction,
-- and stays in the document between the two markers. This rewrites the table
-- and nothing else, and refuses outright if the markers are gone rather than
-- guessing where the table used to be.
--------------------------------------------------------------------------------

local ReadingOrder = {}

ReadingOrder.BEGIN_MARKER = "<!-- begin generated: the count so far -->"
ReadingOrder.END_MARKER   = "<!-- end generated -->"

-- {{{ GROUPS
-- A group directory takes an index of its own, and a directory has no header to
-- read a sentence out of -- so these five sentences live here, in the structure,
-- next to the code that needs them.
--
-- This is also why every file inside a group carries an index one higher than
-- the directory: `src/025-enums/` claimed 025, so the first file in it is 026.
-- Seven banner comments once disagreed with their filenames for exactly this
-- reason; tests/banners.test.lua now states it as a property.
--
-- A new group directory with no entry here is an ERROR, not a skipped row. A
-- silently missing group is how an index disappears from the count.
local GROUPS = {
    ["025-enums"]      = "The closed sets, as members you can compare by identity.",
    ["033-mechanisms"] = "The hands, given one doorway.",
    ["039-memory"]     = "What a creature holds, and for how long.",
    ["041-vision"]     = "Seeing, rather than querying.",
    ["045-toolbox"]    = "Every word in one table, and that table as a tool list.",
}
-- }}}

-- {{{ ENOUGH / TOO_MUCH
-- A row's worth of description, in characters.
--
-- The first sentence alone was the first rule and it cut too close: "Places
-- have names." and "The front door." are true, and tell a reader nothing they
-- could not have got from the filename. An indexed filename is about thirty
-- characters wide, so a description shorter than ENOUGH has barely out-told the
-- name sitting next to it, and the sentence after it comes along too.
--
-- TOO_MUCH is the other guard. Some files open with a short thesis followed by
-- a very long justification -- the whole of why JSON is written here rather than
-- depended on -- and pulling that into a table cell turns the count into an
-- essay. Where the second sentence is that big, the short thesis stands alone.
local ENOUGH   =  48
local TOO_MUCH = 180
-- }}}

-- {{{ sentences_in(paragraph)
-- The paragraph cut into sentences.
--
-- A sentence ends at a period followed by a space and something that starts a
-- new one -- a capital or a backtick. That test is what keeps `3.3.5a` and
-- `scripts/neuron-menu.` from being read as endings: the periods inside them are
-- followed by a digit, a letter mid-word, or nothing at all.
local function sentences_in(paragraph)
    local found, from = {}, 1

    while true do
        local ends = paragraph:find("%. [A-Z`]", from)
        if not ends then break end

        table.insert(found, paragraph:sub(from, ends))
        from = ends + 2
    end

    local last = paragraph:sub(from)
    if last ~= "" then table.insert(found, last) end

    return found
end
-- }}}

-- {{{ summary_from(paragraph)
-- As much of the paragraph as a row wants: the first sentence, and the next one
-- too when the first is too short to say anything and the next is not an essay.
local function summary_from(paragraph)
    local found = sentences_in(paragraph)
    if #found == 0 then return paragraph end

    local summary = found[1]
    local at      = 2

    while #summary < ENOUGH and found[at] do
        local grown = summary .. " " .. found[at]
        if #grown > TOO_MUCH then break end

        summary = grown
        at      = at + 1
    end

    return summary
end
-- }}}

-- {{{ summary_of(path)
-- The file's own first sentence about itself.
--
-- Reads from line 4 to the first blank comment line or the closing rule of
-- dashes. Both terminators matter: most headers separate the summary from the
-- rest with a blank `--`, but a two-line header runs straight into the rule,
-- and stopping only at the blank one swallows sixty dashes into the table.
function ReadingOrder.summary_of(path)
    local file = io.open(path, "r")
    if not file then
        return nil, "cannot open " .. path
    end

    local lines = {}
    local number = 0

    for line in file:lines() do
        number = number + 1

        if number >= 4 then
            if line:match("^%-%-%-%-") then break end        -- the closing rule
            if line:match("^%-%-%s*$") then break end        -- a blank comment
            if not line:match("^%-%-") then break end        -- out of the header

            table.insert(lines, (line:gsub("^%-%-%s?", "")))
        end
    end

    file:close()

    if #lines == 0 then
        return nil, path .. " has no summary on line 4"
    end

    return summary_from((table.concat(lines, " "):gsub("%s+$", "")))
end
-- }}}

-- {{{ ReadingOrder.rows(root)
-- Every indexed thing under src/, in the order somebody should read it.
--
-- Group directories and the files inside them go in one flat list sorted on the
-- index, which puts a directory immediately above its own contents without
-- anything having to arrange that -- the directory's index is lower because it
-- took the lower number.
function ReadingOrder.rows(root)
    local listing = io.popen("find '" .. root .. "/src' -name '*.lua' | sort", "r")
    if not listing then
        return nil, "cannot list " .. root .. "/src"
    end

    local rows, groups_seen = {}, {}

    for path in listing:lines() do
        local short     = path:gsub(".*/src/", "src/")
        local basename  = path:gsub(".*/", "")
        local index     = basename:match("^(%d+)%-")

        if not index then
            listing:close()
            return nil, short .. " has no index on the front of its name"
        end

        local directory = path:match("/src/(%d+%-[^/]+)/")

        if directory and not groups_seen[directory] then
            local describes = GROUPS[directory]

            if not describes then
                listing:close()
                return nil, "src/" .. directory .. "/ is a group directory with "
                    .. "no description.\n  Add one to GROUPS in "
                    .. "src/075-reading-order.lua -- one sentence, saying what "
                    .. "the group is for."
            end

            groups_seen[directory] = true

            table.insert(rows, {
                index     = directory:match("^(%d+)"),
                path      = "src/" .. directory .. "/",
                describes = describes,
            })
        end

        local describes, why = ReadingOrder.summary_of(path)
        if not describes then
            listing:close()
            return nil, why
        end

        table.insert(rows, { index = index, path = short, describes = describes })
    end

    listing:close()

    table.sort(rows, function(a, b)
        if a.index == b.index then return a.path < b.path end
        return tonumber(a.index) < tonumber(b.index)
    end)

    return rows
end
-- }}}

-- {{{ ReadingOrder.table_for(rows)
-- The rows as the markdown table, markers included.
function ReadingOrder.table_for(rows)
    local out = { ReadingOrder.BEGIN_MARKER, "" }

    table.insert(out, "| Index | File | What it adds to the story |")
    table.insert(out, "|-------|------|---------------------------|")

    for _, row in ipairs(rows) do
        table.insert(out, string.format("| %s | `%s` | %s |",
            row.index, row.path, row.describes))
    end

    table.insert(out, "")
    table.insert(out, "*Generated from the source headers by "
        .. "`scripts/reading-order`. To change a line in this table, change the "
        .. "sentence at the top of the file it describes.*")
    table.insert(out, "")
    table.insert(out, ReadingOrder.END_MARKER)

    return table.concat(out, "\n")
end
-- }}}

-- {{{ ReadingOrder.rewrite(document, replacement)
-- The document with everything between the markers swapped out.
--
-- Refuses rather than repairs. A document that has lost its markers has been
-- edited by somebody who did not know the table was generated, and writing a
-- fresh table into it at a guessed position would destroy whatever they wrote.
function ReadingOrder.rewrite(document, replacement)
    local opens  = document:find(ReadingOrder.BEGIN_MARKER, 1, true)
    local closes = document:find(ReadingOrder.END_MARKER, 1, true)

    if not opens or not closes then
        return nil, "docs/reading-order.md has lost its generated-table "
            .. "markers.\n  Expected these two lines, with the table between "
            .. "them:\n    " .. ReadingOrder.BEGIN_MARKER
            .. "\n    " .. ReadingOrder.END_MARKER
            .. "\n  Nothing was written. Put them back and run this again."
    end

    if closes < opens then
        return nil, "docs/reading-order.md has its generated-table markers the "
            .. "wrong way round -- the end marker comes first.\n  Nothing was "
            .. "written."
    end

    return document:sub(1, opens - 1)
        .. replacement
        .. document:sub(closes + #ReadingOrder.END_MARKER)
end
-- }}}

-- {{{ run as a script
-- Reached through scripts/reading-order, which passes the project root and the
-- document to rewrite.
if arg and arg[0] and arg[0]:match("075%-reading%-order%.lua$") then
    local root     = arg[1]
    local document = arg[2]

    -- Quiet suppresses the line saying it worked, and nothing else. The caller
    -- that wants this is --check, which writes to a scratch copy purely to
    -- compare it and has its own answer to give; a failure still has to come
    -- through, because a --check that silently wrote nothing would report
    -- "current" about a comparison that never happened.
    local quiet = (arg[3] == "--quiet")

    if not root or not document then
        io.stderr:write("075-reading-order: needs a project root and a "
            .. "document path\n  usage: luajit src/075-reading-order.lua "
            .. "<root> <docs/reading-order.md> [--quiet]\n")
        os.exit(2)
    end

    local rows, why = ReadingOrder.rows(root)
    if not rows then
        io.stderr:write("075-reading-order: " .. why .. "\n")
        os.exit(1)
    end

    local file, open_why = io.open(document, "r")
    if not file then
        io.stderr:write("075-reading-order: cannot read " .. document
            .. "\n  " .. tostring(open_why) .. "\n")
        os.exit(1)
    end

    local existing = file:read("*a")
    file:close()

    local rewritten, rewrite_why =
        ReadingOrder.rewrite(existing, ReadingOrder.table_for(rows))

    if not rewritten then
        io.stderr:write("075-reading-order: " .. rewrite_why .. "\n")
        os.exit(1)
    end

    local out, write_why = io.open(document, "w")
    if not out then
        io.stderr:write("075-reading-order: cannot write " .. document
            .. "\n  " .. tostring(write_why) .. "\n")
        os.exit(1)
    end

    out:write(rewritten)
    out:close()

    if not quiet then
        io.stderr:write(string.format("wrote %s -- %d entries, highest index %s\n",
            document, #rows, rows[#rows].index))
    end
end
-- }}}

return ReadingOrder
