--------------------------------------------------------------------------------
-- tests/075-reading-order.test.lua
--
-- The properties the generated index rests on.
--
-- This generator replaced a hand-kept table that had gone wrong in three ways
-- at once -- short by twenty-three entries, listing three files that no longer
-- existed, and out of numeric order in a document whose whole claim is that
-- numeric order is the order. Every one of those was invisible: a stale table
-- renders perfectly, and a reader believes it.
--
-- So what is tested here is not that the generator runs. It is that the three
-- ways a generated index can lie are each impossible: that it reads the right
-- line of a header, that it puts rows in the order it promises, and that it
-- refuses rather than guesses when the document it is rewriting has been
-- changed underneath it.
--------------------------------------------------------------------------------

local NEURON = "/mnt/mtwo/games/azeroth-core/wow-chat-neuron"

local ReadingOrder = dofile(NEURON .. "/src/075-reading-order.lua")

local passed, failed = 0, 0

-- {{{ check(label, got, want)
local function check(label, got, want)
    if got == want then
        passed = passed + 1
    else
        failed = failed + 1
        print(string.format("FAIL  %s\n        got  %s\n        want %s",
            label, tostring(got), tostring(want)))
    end
end
-- }}}

-- {{{ summaries come off line 4, and stop where the paragraph stops
local summary = ReadingOrder.summary_of(NEURON .. "/src/050-api.lua")
check("a one-line summary is read whole",
    summary, "One HTTPS request to a model, and the answer back.")

-- The wrapped case: two comment lines joined into one sentence. If the join
-- were missing, this would end mid-clause and nobody would notice, because a
-- half-sentence in a table cell still looks like a table cell.
local wrapped = ReadingOrder.summary_of(NEURON .. "/src/005-world-read.lua")
check("a wrapped summary is joined",
    wrapped,
    "Turns database rows into the small number of record types the rest of "
    .. "the project talks about.")

-- The two-line-header case. This file's summary runs straight into the closing
-- rule with no blank comment line between, and stopping only at a blank one
-- pulled sixty dashes into the table.
local short = ReadingOrder.summary_of(NEURON .. "/src/060-menu-main.lua")
check("the closing rule is not swallowed",
    short:find("%-%-%-%-") == nil, true)
check("a two-line header still reads",
    short, "Start the menu. Reached through scripts/neuron-menu.")

-- A version number is not a sentence ending. `3.3.5a` has two periods in it and
-- both are followed by a digit, which is the whole reason the boundary test
-- looks at what comes AFTER the space rather than just finding a period.
local classes = ReadingOrder.summary_of(NEURON .. "/src/025-enums/032-classes.lua")
check("a version number does not end a sentence",
    classes, "The nine playable classes of 3.3.5a, as an enum.")

-- A missing file is a refusal with a reason, not a nil that becomes an empty
-- table cell further down.
local absent, why = ReadingOrder.summary_of(NEURON .. "/src/999-not-here.lua")
check("a missing file refuses",               absent,               nil)
check("and says why",                         why ~= nil,           true)
-- }}}

-- {{{ the rows are the source tree, in the order the document promises
local rows, rows_why = ReadingOrder.rows(NEURON)

check("the tree was read",                    rows ~= nil,          true)
check("with no complaint",                    rows_why,             nil)

if rows then
    -- Ascending, with no exceptions. This is the document's entire claim.
    local ascending = true
    for at = 2, #rows do
        if tonumber(rows[at].index) < tonumber(rows[at - 1].index) then
            ascending = false
        end
    end
    check("every index is at or above the one before it", ascending, true)

    -- A group directory sits immediately above its own contents, and it gets
    -- there by holding the lower number rather than by anything sorting it.
    local by_path = {}
    for _, row in ipairs(rows) do by_path[row.path] = row end

    check("the enums group is listed",
        by_path["src/025-enums/"] ~= nil, true)
    check("and holds the index below its first file",
        tonumber(by_path["src/025-enums/"].index)
            < tonumber(by_path["src/025-enums/026-enum.lua"].index), true)

    -- Files that were replaced are gone because nothing lists them by hand.
    check("a replaced file is absent",
        by_path["src/022-http-server.lua"],  nil)
    check("and so is the one after it",
        by_path["src/023-chat-main.lua"],    nil)

    -- Every row says something. An empty description is the failure mode of a
    -- header whose shape changed, and it renders as a blank cell rather than as
    -- an error.
    local blank = 0
    for _, row in ipairs(rows) do
        if not row.describes or row.describes == "" then blank = blank + 1 end
    end
    check("no row has an empty description",  blank,                0)
end
-- }}}

-- {{{ rewriting refuses rather than guesses
-- A document that has lost its markers has been edited by somebody who did not
-- know the table was generated. Writing a fresh table in at a guessed position
-- would destroy whatever they wrote, so this is a refusal and not a repair.
local replacement = "GENERATED"

local intact = "before\n" .. ReadingOrder.BEGIN_MARKER .. "\nold\n"
    .. ReadingOrder.END_MARKER .. "\nafter\n"

check("an intact document is rewritten",
    ReadingOrder.rewrite(intact, replacement), "before\nGENERATED\nafter\n")

local no_markers = "before\nold\nafter\n"
local refused, refusal_why = ReadingOrder.rewrite(no_markers, replacement)
check("a document with no markers refuses",   refused,              nil)
check("and names the markers it wanted",
    refusal_why:find(ReadingOrder.BEGIN_MARKER, 1, true) ~= nil, true)

local backwards = "before\n" .. ReadingOrder.END_MARKER .. "\nold\n"
    .. ReadingOrder.BEGIN_MARKER .. "\nafter\n"
local reversed = ReadingOrder.rewrite(backwards, replacement)
check("markers the wrong way round refuse",   reversed,             nil)
-- }}}

-- {{{ the document on disk is current
-- The one property a reader actually depends on. Everything above can pass
-- while docs/reading-order.md still holds last month's table, because nothing
-- in this project reads that document -- only people do.
local on_disk = io.open(NEURON .. "/docs/reading-order.md", "r")
check("the document exists",                  on_disk ~= nil,       true)

if on_disk and rows then
    local text = on_disk:read("*a")
    on_disk:close()

    local current = ReadingOrder.rewrite(text, ReadingOrder.table_for(rows))

    -- Compared line by line, and reported as the first line that differs.
    -- Handing the whole of both documents to the failure printer was the first
    -- shape of this, and it buried one changed row under two hundred identical
    -- ones -- a failure nobody can read is a failure nobody acts on.
    local want, got = {}, {}
    for line in text:gmatch("([^\n]*)\n?")        do table.insert(want, line) end
    for line in (current or ""):gmatch("([^\n]*)\n?") do table.insert(got, line) end

    local differs
    for at = 1, math.max(#want, #got) do
        if want[at] ~= got[at] then
            differs = at
            break
        end
    end

    if differs then
        failed = failed + 1
        print(string.format(
            "FAIL  docs/reading-order.md is out of date, from line %d\n"
            .. "        on disk    %s\n"
            .. "        should be  %s\n"
            .. "        run scripts/reading-order",
            differs, tostring(want[differs]), tostring(got[differs])))
    else
        passed = passed + 1
    end
end
-- }}}

-- {{{ report
print(string.format("075-reading-order: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
-- }}}
