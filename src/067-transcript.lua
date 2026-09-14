--------------------------------------------------------------------------------
-- 067-transcript.lua
--
-- A conversation, as one plain text file that is also the machine's copy.
--
-- There were two files: a readable transcript nobody parsed, and a JSON history
-- nobody read. The same conversation twice, able to disagree, and the JSON one
-- keyed by PORT -- so a new window inherited whatever the last one on that port
-- had been saying.
--
-- One file now, and the readable one is the real one. It is parsed back when a
-- conversation is revived. That ordering matters: a format written to be read
-- by a person and parsed by a machine stays readable, because the person is the
-- one who complains. A format written for the machine and rendered for the
-- person drifts until the rendering is the only honest part.
--
-- TWO FILES, ONE STREAM. The one file became two, split by AUDIENCE:
--
--     2026-09-06/001530-a3f1.txt              what people said
--     2026-09-06/001530-a3f1_for_robots.txt   what the machinery said
--
-- Not by importance -- both halves are essential and the model reads both. The
-- split is about who came to read it. Somebody opening a conversation from last
-- week wanted the conversation, and was shown a thousand characters of system
-- prompt before the first word anybody said, then an eighty-line creature table
-- in the middle of it. That is the plumbing, and it is most of the bytes.
--
--     [you]        human   somebody said it
--     [neuron]     human   the model said it
--     [tool] name  human   which word it reached for, and its arguments
--     [result]     robots  what that call handed back
--     [system]     robots  instructions to a model, not conversation
--
-- A tool call stays on the human side because "it looked up undead creatures
-- around level 12" is part of the story. Its ANSWER does not.
--
-- SECTIONS. Consecutive blocks bound for the same file are one section, and
-- sections are numbered from zero with ONE counter shared by both files. Each
-- file writes a marker where the other's section belongs:
--
--     [from_robots] 7          in the human file
--     [from_conversation] 6    in the robots file
--
-- Stitching is merging by number; the markers are signposts rather than the
-- mechanism. That ordering is deliberate. If one file is truncated or missing,
-- merging by number still yields a correctly ordered partial conversation,
-- where marker-chasing would yield a plausible wrong one.
--
-- A section is also the smallest thing that can be LEFT OUT of what gets sent
-- to a model. Reviving used to be all-or-nothing, because nothing in the format
-- named a piece; now everything has a number. Using those numbers to prune is
-- issue 803's sequel and is not built here.
--
-- Markers sit at the start of a line, nothing else at that indent. Everything
-- after a marker until the next one belongs to it. A line inside a block that
-- happens to begin with "[" is indented by one space on the way in and
-- unindented on the way out, so a model quoting this format cannot forge a
-- turn.
--------------------------------------------------------------------------------

local Transcript = {}

local RULE = string.rep("=", 78)

-- {{{ WHERE
-- Which marker belongs in which file.
--
-- A dispatch table rather than a chain of comparisons, so that adding a kind of
-- block is one row here and nothing else -- and so the whole rule can be read
-- at once, which is the thing somebody wants when a block turns up in the wrong
-- half.
local WHERE = {
    you    = "human",
    neuron = "human",
    tool   = "human",
    result = "robots",
    system = "robots",
}

-- The marker one file writes where the other file's section belongs. Named for
-- what you would FIND there rather than for where you are: reading the human
-- file, "[from_robots] 7" says section seven is over in the robots file.
local POINTER = { human = "from_robots", robots = "from_conversation" }
-- }}}

-- {{{ Transcript.path(handle, id, which)
-- Where a conversation lives. The id carries its own date, so the file sorts
-- chronologically and the directory is one day.
--
-- `which` is "human" (the default) or "robots". One function, so the naming
-- rule lives in exactly one place -- a second `.. "_for_robots.txt"` built by
-- concatenation somewhere else is a path that stays right until the day this
-- one changes.
function Transcript.path(handle, id, which)
    local date = id:match("^(%d%d%d%d%-%d%d%-%d%d)") or os.date("%Y-%m-%d")
    local name = id:gsub("^%d%d%d%d%-%d%d%-%d%d/", "")

    return string.format("%s/logs/asking/%s/%s%s.txt",
        handle.neuron_root, date, name,
        which == "robots" and "_for_robots" or "")
end
-- }}}

-- {{{ Transcript.split(handle, id)
-- Is this conversation two files, or one from before the split?
--
-- Asked rather than assumed, and the answer is carried rather than guessed at
-- each call site. A transcript with no robots file beside it was written before
-- this format existed; it is read whole, and it is SAID that it was, because a
-- compatibility path nobody is told about is a fallback and a fallback is a
-- warning.
function Transcript.split(handle, id)
    local robots = io.open(Transcript.path(handle, id, "robots"), "r")
    if not robots then return false end
    robots:close()
    return true
end
-- }}}

-- {{{ Transcript.new_id()
-- Sortable, unique, and readable: the date, the time, and enough randomness
-- that two conversations begun in the same second are still two.
function Transcript.new_id()
    return string.format("%s/%s-%04x",
        os.date("%Y-%m-%d"), os.date("%H%M%S"), math.random(0, 0xffff))
end
-- }}}

-- {{{ MARKER_LINE / POINTER_LINE
-- How a marker line is recognised, and how its section number is read off it.
--
--     [you] #3
--     [tool] world_creatures #4
--     [from_robots] #5
--
-- Two patterns because the two must never be confused. A pointer carries the
-- number of a section in the OTHER file, so counting it as one of this file's
-- own would put a section on the wrong side of the split -- which reads as the
-- conversation being shuffled rather than as a parsing mistake.
local function marker_of(line)
    local marker, rest = line:match("^%[([%a_]+)%]%s*(.*)$")
    if not marker then return nil end

    local number = rest:match("#(%d+)%s*$")
    local name   = rest:gsub("%s*#%d+%s*$", "")

    return marker, (name ~= "" and name or nil), tonumber(number)
end

local function is_pointer(marker)
    return marker == "from_robots" or marker == "from_conversation"
end
-- }}}

-- {{{ where_it_stands(handle, id)
-- The next section number, and which half the last block went to.
--
-- Read off the FILES rather than kept in memory, because nothing else about a
-- conversation is in memory either: the transcript is the conversation. A
-- counter living in a process would reset when the menu restarted and start
-- handing out numbers that already exist, silently merging two sections into
-- one on the next read.
--
-- Costs a scan of two small text files per appended block. The same turn
-- already reads the whole conversation back to build the model's messages, so
-- this is not a new order of cost -- and it is the price of the file being the
-- only state there is.
--
-- Returns: the highest section number so far (-1 if none), and which file the
-- last block was in (nil if none).
local function where_it_stands(handle, id)
    local highest, in_file = -1, nil

    for _, which in ipairs({ "human", "robots" }) do
        local file = io.open(Transcript.path(handle, id, which), "r")
        if file then
            for line in file:lines() do
                local marker, _, number = marker_of(line)
                if marker and number and not is_pointer(marker) then
                    if number > highest then
                        highest, in_file = number, which
                    end
                end
            end
            file:close()
        end
    end

    return highest, in_file
end
-- }}}

-- {{{ shield(text) / unshield(text)
-- A line beginning with a marker, inside a block, would parse as a new turn.
-- Indented by one space on the way in and restored on the way out -- so a model
-- that writes "[you]" at the start of a line cannot invent a person saying
-- something.
local function shield(text)
    return (tostring(text or ""):gsub("\n(%[)", "\n %1"):gsub("^(%[)", " %1"))
end

local function unshield(text)
    return (tostring(text or ""):gsub("\n (%[)", "\n%1"):gsub("^ (%[)", "%1"))
end
-- }}}

-- {{{ Transcript.begin(handle, id, about)
-- Start the file. Called once, when a conversation is first spoken to.
function Transcript.begin(handle, id, about)
    local path = Transcript.path(handle, id)

    os.execute("mkdir -p '" .. path:match("^(.*)/[^/]*$") .. "'")

    -- The SAME header on both halves.
    --
    -- Not duplication for its own sake: either file can be opened alone, by
    -- somebody in a text editor who has no idea the other exists, and a file
    -- that cannot say which conversation it is a half of is a file that will
    -- eventually be deleted by somebody tidying up.
    local header = RULE .. "\n"
        .. string.format("neuron conversation %s\n", id)
        .. string.format("started %s   levers %s   profile %s\n",
            os.date("%Y-%m-%d %H:%M:%S"), about.vocabulary or "world",
            about.profile or "?")
        .. RULE .. "\n\n"

    for _, which in ipairs({ "human", "robots" }) do
        local file = io.open(Transcript.path(handle, id, which), "a")
        if not file then
            return nil, "cannot write " .. Transcript.path(handle, id, which)
        end
        file:write(header)
        file:close()
    end

    -- Section zero is the instructions, and they are the machine's half. This
    -- used to be the first thing a person saw when they opened a conversation
    -- from last week: a thousand characters of prompt before the first word
    -- anybody said.
    if about.system then
        Transcript.append(handle, id, "system", about.system)
    end

    return path
end
-- }}}

-- {{{ Transcript.append(handle, id, marker, text, name)
-- One turn. Appended, never rewritten -- a conversation is a thing that
-- happened, and a file you can edit is a record you cannot trust.
function Transcript.append(handle, id, marker, text, name)
    local which = WHERE[marker]

    if not which then
        -- Not a silent default. A block with no home is a marker somebody added
        -- to one file and forgot to add to WHERE, and putting it in the human
        -- half "just in case" is how the machine's plumbing leaks back into the
        -- thing a person came to read.
        error(string.format(
            "067-transcript: '%s' is not a kind of block. WHERE says which half "
         .. "each kind belongs to and it has no row for this one -- add it "
         .. "there, deciding whether a person or a model is its audience.",
            tostring(marker)))
    end

    local highest, previous = where_it_stands(handle, id)

    -- A SECTION IS A MAXIMAL RUN. Consecutive blocks bound for the same half
    -- share a number -- an assistant turn and the three tool calls it made are
    -- one thing, not four, and pruning them apart would leave calls whose
    -- answers went missing.
    --
    -- Numbering every block separately was the first version of this and it was
    -- wrong in a way that only shows up later: sections stop alternating, so a
    -- pointer no longer names exactly one section on the other side, and one
    -- pointer has to stand in for several.
    local section = (previous == which) and highest or (highest + 1)

    local file = io.open(Transcript.path(handle, id, which), "a")
    if not file then return end

    -- The stream crossed over, so the file being written notes where the other
    -- one picks up. A signpost rather than the mechanism -- reading merges by
    -- number -- but it is what makes one half readable ALONE, which is most of
    -- why the split is worth having.
    if previous and previous ~= which then
        local other = io.open(Transcript.path(handle, id, previous), "a")
        if other then
            other:write(string.format("[%s] #%d\n\n",
                POINTER[previous], section))
            other:close()
        end
    end

    file:write(string.format("[%s]%s #%d\n",
        marker, name and (" " .. name) or "", section))
    file:write(shield(text) .. "\n\n")
    file:close()
end
-- }}}

-- {{{ blocks_of(path)
-- One file, as an ordered list of { marker, name, section, text }.
--
-- SIGNPOSTS ARE KEPT. They were dropped when reading merged by number, because
-- then they carried nothing the merge needed. They direct traffic now: reading
-- follows them, so a reader that threw them away would have no idea where to
-- go. Callers that want only the conversation filter them out themselves.
local function blocks_of(path)
    local file = io.open(path, "r")
    if not file then return {} end

    local blocks, current = {}, nil

    for line in file:lines() do
        local marker, name, section = marker_of(line)

        if marker then
            if current then table.insert(blocks, current) end

            current = { marker = marker, name = name, section = section,
                        lines = {} }
        elseif current then
            table.insert(current.lines, line)
        end
    end

    file:close()
    if current then table.insert(blocks, current) end

    for _, block in ipairs(blocks) do
        -- Trailing blank lines are the separator, not content.
        while #block.lines > 0 and block.lines[#block.lines] == "" do
            table.remove(block.lines)
        end
        block.text = unshield(table.concat(block.lines, "\n"))
        block.lines = nil
    end

    return blocks
end
-- }}}

-- {{{ follow(human, robots)
-- Walk the two halves by following the signposts.
--
-- SIGNPOSTS, NOT BORDERS. This is the whole reading model and it is worth
-- saying plainly, because the first version did something else and the
-- difference is not cosmetic.
--
-- The first version numbered every section and merged by sorting the numbers.
-- That makes a number a BORDER: it declares "this section contains exactly
-- these blocks", and then every question about the format becomes a question
-- about what a section is allowed to contain. Is one tool call a section? Is a
-- turn plus its three calls one section or three? The format starts having
-- opinions about the conversation.
--
-- A signpost declares nothing about what it separates. It says one thing --
-- READ THE OTHER FILE NEXT -- and that is a direction, not a boundary. At each
-- intersection exactly one way is valid, and the sign points at it. However
-- much sits on the far side is however much sits there; the format has no
-- opinion, and there is no such thing as a wrongly sized section.
--
-- The numbers survive as LABELS, so an atom can be named by an edit log. They
-- are no longer the thing that decides order.
--
-- Returns the blocks in the order they happened, and a list of anything the
-- walk could not account for.
local function follow(human, robots)
    local road = { human = { blocks = human, at = 1 },
                   robots = { blocks = robots, at = 1 } }

    -- Which half the stream starts in. Whichever holds the lowest-numbered
    -- block -- the instructions are section zero and they are the machine's,
    -- so in practice this is always "robots", but reading it rather than
    -- assuming it means a conversation that begins some other way still works.
    local function first_number(side)
        for _, block in ipairs(road[side].blocks) do
            if not is_pointer(block.marker) then return block.section or 0 end
        end
        return math.huge
    end

    local here = (first_number("robots") <= first_number("human"))
        and "robots" or "human"

    local out, trouble = {}, {}
    local steps = 0
    local total = #human + #robots

    -- Bounded by the number of blocks there are. A signpost pointing at a half
    -- that has nothing left would otherwise bounce the walk back and forth
    -- forever, and a reader that hangs is worse than one that says it is lost.
    while steps <= total + 2 do
        steps = steps + 1

        local side  = road[here]
        local block = side.blocks[side.at]

        if not block then
            -- This half is finished. If the other one still has blocks, the
            -- conversation crosses over one last time without a signpost --
            -- which happens when the last thing written was a crossing that
            -- never came back.
            local other = (here == "human") and "robots" or "human"
            if road[other].blocks[road[other].at] then
                here = other
            else
                break
            end
        elseif is_pointer(block.marker) then
            side.at = side.at + 1
            here = (here == "human") and "robots" or "human"
        else
            side.at = side.at + 1
            table.insert(out, block)
        end
    end

    -- Anything the walk never reached. Not silently dropped: a block that
    -- exists and did not come back means a signpost is missing, and a
    -- conversation quietly missing a turn is the failure that looks like
    -- nothing at all.
    for _, side in pairs(road) do
        for index = side.at, #side.blocks do
            if not is_pointer(side.blocks[index].marker) then
                table.insert(trouble, side.blocks[index])
            end
        end
    end

    return out, trouble
end
-- }}}

-- {{{ Transcript.blocks(handle, id, which)
-- The conversation, as an ordered list of { marker, name, section, text }.
--
-- With no `which`, both halves walked by following the signposts. With "human"
-- or "robots", just that one, signposts filtered out -- which is what the
-- prior-conversation viewer wants, and what makes reading cheap for a page
-- that is only going to show what people said.
function Transcript.blocks(handle, id, which)
    if which then
        local out = {}
        for _, block in ipairs(blocks_of(Transcript.path(handle, id, which))) do
            if not is_pointer(block.marker) then table.insert(out, block) end
        end
        return out
    end

    -- No robots file means a conversation from before the split. It is read
    -- whole, out of the one file it has.
    if not Transcript.split(handle, id) then
        return blocks_of(Transcript.path(handle, id, "human"))
    end

    local walked, stranded = follow(
        blocks_of(Transcript.path(handle, id, "human")),
        blocks_of(Transcript.path(handle, id, "robots")))

    -- Numbers are labels now, but they are still a second opinion about order,
    -- and a second opinion is worth having when the first one is a walk through
    -- two files that could disagree. This does not reorder anything -- it says
    -- so, in the returned list, where a caller can show it.
    local slipped = 0
    local highest = -1
    for _, block in ipairs(walked) do
        local number = block.section or 0
        if number < highest then slipped = slipped + 1 end
        highest = math.max(highest, number)
    end

    if #stranded > 0 or slipped > 0 then
        walked.trouble = string.format(
            "%d block(s) were never reached by following the signposts, and "
         .. "%d arrived out of numbered order. A signpost is missing or a half "
         .. "was truncated. Nothing has been reordered -- what is above is what "
         .. "the signs actually say.", #stranded, slipped)
    end

    return walked
end
-- }}}

-- {{{ the edit log
-- What has been pruned out of a conversation, and how it got that way.
--
-- A third file beside the two halves:
--
--     2026-09-06/011530-a3f1_edits.txt
--
--     # 2026-09-06T01:45:12  over budget by 8k
--     drop 12
--     fold 13 14 15  asked about creature levels three times
--     # 2026-09-06T02:10:03  wanted it back
--     keep 12
--
-- APPEND-ONLY, AND REPLAYED FROM THE START. Every read walks the log in order
-- over a table of atoms, so the current state is derived rather than stored.
--
-- The alternative was rewriting the section list in place, which is cheaper and
-- destroys the record of what was pruned and why. Same reason `append` never
-- rewrites a transcript: an edit log that can be edited is a record you cannot
-- trust, and the whole value of knowing a conversation was cut down is knowing
-- what came out of it. Replay costs one pass over a file with a handful of
-- lines in it.
--
-- `keep` is how an edit is undone. The log only ever grows.

-- {{{ Transcript.edits_path(handle, id)
function Transcript.edits_path(handle, id)
    return (Transcript.path(handle, id, "human"):gsub("%.txt$", "_edits.txt"))
end
-- }}}

-- {{{ Transcript.edits(handle, id)
-- The log, replayed. Returns a table keyed by section number:
--
--     { [12] = { state = "dropped" },
--       [13] = { state = "folded", says = "asked three times", leads = true },
--       [14] = { state = "folded" } }
--
-- A section not in the table is kept, which is the state everything starts in.
-- `leads` marks the one atom of a fold that carries the replacement text, so a
-- rebuild puts one block where several were rather than one per atom.
function Transcript.edits(handle, id)
    local state = {}

    local file = io.open(Transcript.edits_path(handle, id), "r")
    if not file then return state end

    for line in file:lines() do
        -- A comment carries the when and the why. It is for whoever opens the
        -- file, and it is skipped here: the operations are the log.
        if not line:match("^%s*#") and line:match("%S") then
            local verb, rest = line:match("^%s*(%a+)%s*(.*)$")

            if verb == "drop" then
                for number in rest:gmatch("%d+") do
                    state[tonumber(number)] = { state = "dropped" }
                end

            elseif verb == "keep" then
                for number in rest:gmatch("%d+") do
                    state[tonumber(number)] = nil
                end

            elseif verb == "fold" then
                -- `fold 13 14 15  what it said instead`. The numbers run until
                -- the first thing that is not one; everything after is the
                -- replacement.
                local numbers, says = rest:match("^([%d%s]*)(.*)$")
                local first = true
                for number in (numbers or ""):gmatch("%d+") do
                    state[tonumber(number)] = { state = "folded",
                        says = first and (says ~= "" and says or nil) or nil,
                        leads = first }
                    first = false
                end
            end
        end
    end

    file:close()
    return state
end
-- }}}

-- {{{ Transcript.prune(handle, id, verb, sections, says, why)
-- Add one line to the log. Nothing else is touched.
--
-- The transcript files are not rewritten and never will be. What a
-- conversation was is not up for revision; what gets SENT is.
function Transcript.prune(handle, id, verb, sections, says, why)
    if verb ~= "drop" and verb ~= "keep" and verb ~= "fold" then
        error("067-transcript: '" .. tostring(verb) .. "' is not an edit. "
           .. "The log holds drop, keep and fold.")
    end

    local numbers = {}
    for _, number in ipairs(sections or {}) do
        table.insert(numbers, tostring(number))
    end

    if #numbers == 0 then
        return nil, "an edit has to name at least one atom."
    end

    if verb == "fold" and (not says or says == "") then
        return nil, "a fold has to say what it says instead. Folding several "
                 .. "exchanges into nothing is a drop, and it should say so."
    end

    local file = io.open(Transcript.edits_path(handle, id), "a")
    if not file then
        return nil, "cannot write " .. Transcript.edits_path(handle, id)
    end

    file:write(string.format("# %s  %s\n",
        os.date("%Y-%m-%dT%H:%M:%S"), why or "no reason given"))
    file:write(string.format("%s %s%s\n", verb, table.concat(numbers, " "),
        (verb == "fold") and ("  " .. says) or ""))
    file:close()

    return true
end
-- }}}

-- {{{ Transcript.atoms(handle, id)
-- Every atom, with what it holds and what has been done to it.
--
-- For whoever decides what to prune. An atom is a run of blocks between two
-- signposts -- however much sits there, because a signpost declares a direction
-- and not a size.
function Transcript.atoms(handle, id)
    local edits = Transcript.edits(handle, id)
    local seen, order = {}, {}

    for _, block in ipairs(Transcript.blocks(handle, id)) do
        local number = block.section or 0
        local atom = seen[number]

        if not atom then
            atom = { section = number, markers = {}, blocks = 0,
                     characters = 0, opens = block.text, texts = {} }
            seen[number] = atom
            table.insert(order, atom)
        end

        table.insert(atom.markers, block.marker)
        table.insert(atom.texts, block.text or "")
        atom.blocks     = atom.blocks + 1
        atom.characters = atom.characters + #(block.text or "")
    end

    for _, atom in ipairs(order) do
        atom.state = (edits[atom.section] or {}).state or "kept"
        atom.says  = (edits[atom.section] or {}).says
        -- Everything in the atom, for matching against. `opens` is the first
        -- seventy-two characters and is for SHOWING -- matching on it meant a
        -- quotation from the middle of a long atom scored near zero against the
        -- atom it came from.
        atom.text  = table.concat(atom.texts, "\n")
        atom.texts = nil
        atom.opens = (atom.opens or ""):gsub("%s+", " "):sub(1, 72)
    end

    return order
end
-- }}}

-- {{{ Transcript.rebuild(handle, id)
-- The conversation as it will be SENT: the walk, with the log replayed over it.
--
-- The files are untouched, and so is what a person sees. Pruning is about the
-- model's budget, not about hiding a conversation from the person having it.
-- {{{ NOT_REPLAYED
-- Calls whose own record is left out of what goes back to the model.
--
-- One member: forgetting. If the act of forgetting were replayed, this whole
-- mechanism would be absurd -- every deletion would add a tool call and a
-- result to the context, so shortening the conversation would make it longer.
--
-- The call and its answer stay in the TRANSCRIPT, where a person can read what
-- the model chose to drop and why. They are simply not sent back to it. The
-- model does not need to remember forgetting; it needs the room.
local NOT_REPLAYED = { ["memory_forget"] = true, ["memory.forget"] = true }

-- Blocks that are for the PERSON and are never sent.
--
-- The opening -- the FAQ -- is the one. It is a page of shell commands for
-- setting up keys and starting ollama, written for somebody sitting at a
-- terminal, and it is the first thing in every conversation. Giving it to a
-- model bought one thing, an opening that was already on screen so it would not
-- greet twice, and cost several: llama3.2 read the commands as instructions and
-- echoed `$EDITOR /mnt/.../secrets.conf` back as though it had done something.
--
-- It stays in the transcript, where it is drawn with the FAQ's own formatting
-- and is exactly what it looks like: a note to the reader.
local NOT_SENT = { faq = true }
-- }}}

function Transcript.rebuild(handle, id)
    local edits = Transcript.edits(handle, id)
    local out, cut = {}, 0

    -- Set when a NOT_REPLAYED call is skipped, so the `[result]` that follows
    -- it goes too. A result with no call is rejected by the API outright, and
    -- dropping only half a pair is how that happens.
    local drop_next_result = false

    for _, block in ipairs(Transcript.blocks(handle, id)) do
        local edit = edits[block.section or 0]

        if NOT_SENT[block.name or ""] then
            drop_next_result = false
            cut = cut + 1

        elseif block.marker == "tool" and NOT_REPLAYED[block.name or ""] then
            drop_next_result = true
            cut = cut + 1

        elseif block.marker == "result" and drop_next_result then
            drop_next_result = false
            cut = cut + 1

        elseif not edit then
            drop_next_result = false
            table.insert(out, block)

        elseif edit.state == "folded" and edit.leads then
            drop_next_result = false
            -- One block where several were. The scar is deliberate: a model
            -- told that something is missing behaves better than one handed a
            -- silent gap, because a gap it cannot see is a gap it will assume
            -- was never there.
            table.insert(out, { marker = "neuron", section = block.section,
                text = "[" .. edit.says .. "]" })
            cut = cut + 1

        else
            cut = cut + 1
        end
    end

    return out, cut
end
-- }}}
-- }}}

-- {{{ Transcript.messages(handle, id)
-- The conversation as the model needs to see it.
--
-- Tool calls and their results are rebuilt as the block pairs the API expects,
-- with ids minted here. The ids only have to agree WITHIN this reconstruction
-- -- nothing outside remembers what they were, which is why they can be
-- regenerated from a text file at all.
function Transcript.messages(handle, id)
    local messages = {}
    local pending_assistant, pending_results = nil, nil

    -- REBUILT, not read raw. The edit log is replayed here and nowhere else,
    -- because this is the only reader whose output is spent: what a person sees
    -- costs nothing, and what goes to a model costs context.
    local blocks = Transcript.rebuild(handle, id)

    -- {{{ flush()
    local function flush()
        if pending_assistant then
            table.insert(messages,
                { role = "assistant", content = pending_assistant })
            pending_assistant = nil
        end
        if pending_results then
            table.insert(messages, { role = "user", content = pending_results })
            pending_results = nil
        end
    end
    -- }}}

    local call_number = 0

    for _, block in ipairs(blocks) do
        if block.marker == "you" then
            flush()
            table.insert(messages, { role = "user", content = block.text })

        elseif block.marker == "neuron" then
            flush()
            pending_assistant = { { type = "text", text = block.text } }

        elseif block.marker == "tool" then
            -- A call belongs to the assistant turn it was part of.
            pending_assistant = pending_assistant or {}
            pending_results   = pending_results or {}

            call_number = call_number + 1
            local identifier = string.format("revived_%d", call_number)

            -- Arguments are `key=value`, separated by TWO spaces, on one
            -- line. Split on the separator first and on the first `=` second.
            --
            -- The pattern used to be `([%w_]+)=([^\n]*)`, which took everything
            -- to the end of the line as the first value: a call written
            -- `type=undead  level=12` came back with type set to
            -- "undead  level=12" and no level at all. It looked right in the
            -- file and was wrong the moment a call had two arguments.
            local arguments = {}
            for pair in (block.text or ""):gmatch("[^\n]+") do
                for piece in (pair .. "  "):gmatch("(.-)  +") do
                    local key, value = piece:match("^([%w_]+)=(.*)$")
                    if key then arguments[key] = value end
                end
            end

            table.insert(pending_assistant, {
                type = "tool_use", id = identifier,
                name = block.name or "unknown", input = arguments,
            })

            -- The result block that follows fills this in; if the file ends
            -- here, the placeholder keeps the pairing valid rather than leaving
            -- a call with no answer, which the API rejects outright.
            table.insert(pending_results, {
                type = "tool_result", tool_use_id = identifier,
                content = "(the conversation ended before this returned)",
            })

        elseif block.marker == "result" then
            if pending_results and #pending_results > 0 then
                pending_results[#pending_results].content = block.text
            end
        end
    end

    flush()

    -- A CONVERSATION MUST BEGIN WITH A PERSON.
    --
    -- The Anthropic API refuses a first message in the assistant role outright.
    -- Ollama tolerates it, so an opening assistant turn was invisible on the
    -- bench and would have failed on the first real request.
    --
    -- The FAQ used to be that turn and is now excluded from the rebuild
    -- entirely, so in practice this finds nothing. It stays because "the first
    -- message is a person" is a property of the API rather than a fact about
    -- the FAQ, and the next thing that opens a conversation should not have to
    -- rediscover it.
    while messages[1] and messages[1].role == "assistant" do
        table.remove(messages, 1)
    end

    return messages
end
-- }}}

-- {{{ Transcript.summary(handle, id)
-- What a listing needs: the opening sentence, when, how many turns.
function Transcript.summary(handle, id)
    -- The human half only. Everything a listing shows -- the opening line, how
    -- many turns, how many calls -- lives there, and reading the machine's half
    -- to count things that are not in it costs a file read per conversation on
    -- a page that lists sixty of them.
    local blocks = Transcript.blocks(handle, id, "human")

    local asked, turns, calls = nil, 0, 0
    for _, block in ipairs(blocks) do
        if block.marker == "you" then
            turns = turns + 1
            asked = asked or block.text
        elseif block.marker == "tool" then
            calls = calls + 1
        end
    end

    return {
        id     = id,
        asked  = asked or "(nothing said)",
        turns  = turns,
        calls  = calls,
        empty  = turns == 0,
        -- Said out loud rather than handled quietly. A conversation with no
        -- robots file beside it was written before the split and is read whole
        -- out of its one file; that path is a compatibility path, and a
        -- compatibility path nobody is told about is a fallback.
        old_format = not Transcript.split(handle, id),
    }
end
-- }}}

-- {{{ Transcript.list(handle, limit)
-- Every conversation, newest first.
function Transcript.list(handle, limit)
    -- The robots halves are excluded by the glob rather than filtered after,
    -- so `limit` still means what it says: without this, asking for sixty
    -- conversations returned thirty conversations and thirty of their machine
    -- halves, and half the list was empty.
    local pipe = io.popen(string.format(
        "ls -1t %s 2>/dev/null | grep -v '_for_robots[.]txt$' | head -n %d",
        "'" .. handle.neuron_root .. "/logs/asking'/*/*.txt", limit or 60), "r")

    if not pipe then return {} end

    local found = {}
    for path in pipe:lines() do
        local id = path:gsub("^.*/logs/asking/", ""):gsub("%.txt$", "")
        local summary = Transcript.summary(handle, id)
        if not summary.empty then table.insert(found, summary) end
    end
    pipe:close()

    return found
end
-- }}}

-- {{{ Transcript.stitched(handle, id)
-- Both halves, merged, rendered back as the one text the format used to be.
--
-- For the live chat window, which draws itself from the transcript and wants
-- everything: what was said, what was called, and what came back. The split is
-- about who came to READ a conversation later, not about hiding the machinery
-- from the window it is happening in.
--
-- Rendered from merged blocks rather than by concatenating the files, because
-- concatenating them would put every result after every sentence.
function Transcript.stitched(handle, id)
    local blocks = Transcript.blocks(handle, id)
    if #blocks == 0 then return nil end

    local out = {}

    for _, block in ipairs(blocks) do
        table.insert(out, string.format("[%s]%s\n%s\n",
            block.marker, block.name and (" " .. block.name) or "",
            shield(block.text)))
    end

    return table.concat(out, "\n")
end
-- }}}

-- {{{ Transcript.human(handle, id)
-- The half a person reads, rendered as text.
--
-- What the live chat window draws itself from, what a revived conversation
-- shows, and what anybody watching a shared conversation sees. Everything a
-- person is shown comes through here.
--
-- It carries the tool lines -- "it looked up undead creatures around level 12"
-- is part of the story -- and not the answers to them, which are eighty lines
-- of table, nor the instructions, which are not conversation.
function Transcript.human(handle, id)
    local out = {}

    for _, block in ipairs(Transcript.blocks(handle, id, "human")) do
        table.insert(out, string.format("[%s]%s\n%s\n",
            block.marker, block.name and (" " .. block.name) or "",
            shield(block.text)))
    end

    if #out == 0 then return nil end
    return table.concat(out, "\n")
end
-- }}}

-- {{{ Transcript.said(handle, id)
-- Only what people said, as text.
--
-- The human half, filtered further to `you` and `neuron`. Somebody opening a
-- conversation from last week came for the conversation -- not the calls it
-- made, and certainly not the instructions it was given. The tool lines stay in
-- the FILE, because "it looked up undead creatures around level 12" is part of
-- the story when you are reading the file itself; they are just not what the
-- list on the menu is for.
function Transcript.said(handle, id)
    local out = {}

    for _, block in ipairs(Transcript.blocks(handle, id, "human")) do
        if block.marker == "you" or block.marker == "neuron" then
            table.insert(out, string.format("[%s]\n%s\n",
                block.marker, shield(block.text)))
        end
    end

    if #out == 0 then return nil end
    return table.concat(out, "\n")
end
-- }}}

-- {{{ Transcript.read(handle, id, which)
-- A file itself, for showing. Defaults to the human half.
--
-- The chat window renders blocks rather than this, so what this is really for
-- is the prior-conversation viewer and anything that wants the file as it sits
-- on disk. Both of those want what people said.
function Transcript.read(handle, id, which)
    local file = io.open(Transcript.path(handle, id, which or "human"), "r")
    if not file then return nil end
    local text = file:read("*a")
    file:close()
    return text
end
-- }}}

return Transcript
