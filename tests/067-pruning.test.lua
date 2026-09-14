--------------------------------------------------------------------------------
-- 067-pruning.test.lua
--
-- Atoms, the edit log, and what a rebuilt conversation looks like.
--
-- Two design decisions are under test here, and both were choices with a real
-- alternative:
--
-- SIGNPOSTS, NOT BORDERS. Reading follows the pointers between the two halves
-- rather than sorting section numbers. A signpost declares a DIRECTION and says
-- nothing about what sits on the far side, so there is no such thing as a
-- wrongly sized section and the format holds no opinion about whether a turn
-- and its three calls are one thing or four.
--
-- APPEND-ONLY, REPLAYED. The log only grows, and the current state is derived
-- by walking it from the start. Rewriting the section list in place would be
-- cheaper and would destroy the record of what was cut and why.
--------------------------------------------------------------------------------

local ROOT       = "/mnt/mtwo/games/azeroth-core/wow-chat-neuron"
local Transcript = dofile(ROOT .. "/src/067-transcript.lua")

local passed, failed = 0, 0

-- {{{ check(what, got, want)
local function check(what, got, want)
    if got == want then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL  " .. what)
        print("        got  " .. tostring(got))
        print("        want " .. tostring(want))
    end
end
-- }}}

local WORK = "/tmp/claude-1000/-mnt-mtwo-games-azeroth-core-wow-chat-neuron/"
          .. "bedafefb-6053-4b5b-b904-cb058c036837/scratchpad/pruning-test"
os.execute("rm -rf '" .. WORK .. "'")
os.execute("mkdir -p '" .. WORK .. "/logs/asking'")

local HANDLE = { neuron_root = WORK }
local id = "2026-09-06/130000-beef"

-- {{{ a conversation with three exchanges in it
Transcript.begin(HANDLE, id, { vocabulary = "world", profile = "vanilla",
                               system = "You operate a world." })

Transcript.append(HANDLE, id, "you",    "what undead are there at twelve")
Transcript.append(HANDLE, id, "tool",   "type=undead  level=12", "world_creatures")
Transcript.append(HANDLE, id, "result", "a long table of ghouls")
Transcript.append(HANDLE, id, "neuron", "Four kinds.")

Transcript.append(HANDLE, id, "you",    "and at fourteen")
Transcript.append(HANDLE, id, "tool",   "type=undead  level=14", "world_creatures")
Transcript.append(HANDLE, id, "result", "another long table")
Transcript.append(HANDLE, id, "neuron", "Six kinds.")

Transcript.append(HANDLE, id, "you",    "spawn three of the first")
-- }}}

-- {{{ following the signs reproduces what happened
local blocks = Transcript.blocks(HANDLE, id)

local order = {}
for _, b in ipairs(blocks) do table.insert(order, b.marker) end

check("every block is reached",                          #blocks,          10)
check("nothing was stranded",                      blocks.trouble,        nil)
check("the instructions are first",                     order[1],   "system")
check("then the first question",                        order[2],      "you")
check("its call",                                       order[3],     "tool")
check("its answer",                                     order[4],   "result")
check("the sentence after it",                          order[5],   "neuron")
check("the second question",                            order[6],      "you")
check("and the last thing said",                       order[10],      "you")
-- }}}

-- {{{ atoms are runs between signposts, whatever size that is
local atoms = Transcript.atoms(HANDLE, id)

check("there are six atoms",                             #atoms,            6)
check("the instructions are one",                atoms[1].section,          0)
check("everything starts kept",                    atoms[1].state,     "kept")

-- The point of "signposts, not borders": a question, its call, and the
-- sentence that follows are one atom because that is what sits between two
-- signs. Nothing decided that a turn "should" be an atom.
-- Section 1 is the question and its call. Section 2 is the answer, alone,
-- because the answer is the machine's half. Section 3 is everything that
-- happened next on the human side before the next crossing: the sentence
-- replying to the first lookup, the SECOND question, and the second call.
-- Nothing decided that was three blocks -- it is what sits between two signs.
check("a question and its call are one atom",      atoms[2].blocks,          2)
check("the answer is the next, alone",             atoms[3].blocks,          1)
check("and the run after it is three blocks long", atoms[4].blocks,          3)
-- }}}

-- {{{ dropping one, and putting it back
-- Section 2: the first lookup's answer, which is the long table.
check("an atom can be dropped",
    Transcript.prune(HANDLE, id, "drop", { 2 }, nil, "the table is huge"), true)

check("the log says so",
    Transcript.edits(HANDLE, id)[2].state,                           "dropped")

local rebuilt, cut = Transcript.rebuild(HANDLE, id)
check("the rebuild leaves it out",                       #rebuilt,          9)
check("and says how much it cut",                             cut,          1)

check("the FILES are untouched",       #Transcript.blocks(HANDLE, id),     10)

-- keep is how an edit is undone, and the log still only grows.
Transcript.prune(HANDLE, id, "keep", { 2 }, nil, "wanted it back")

check("keeping it puts it back",         #Transcript.rebuild(HANDLE, id),  10)
check("and the log grew rather than shrank",
    (function()
        local file = io.open(Transcript.edits_path(HANDLE, id), "r")
        local text = file:read("*a")
        file:close()
        local lines = 0
        for _ in text:gmatch("[^\n]+") do lines = lines + 1 end
        return lines                       -- two comments and two operations
    end)(),                                                                 4)
-- }}}

-- {{{ folding several into one line
check("a fold has to say what it says instead",
    Transcript.prune(HANDLE, id, "fold", { 2, 3 }, nil, "no text"),       nil)

-- Sections 2 and 3 together are four blocks: the first table, the sentence
-- about it, the second question, and the second call.
Transcript.prune(HANDLE, id, "fold", { 2, 3 },
    "looked up undead twice and reported them", "over budget")

local folded = Transcript.rebuild(HANDLE, id)

check("four blocks became one",                           #folded,          7)

local scar = nil
for _, b in ipairs(folded) do
    if (b.text or ""):find("looked up undead twice", 1, true) then scar = b end
end

check("and it leaves a visible scar",             scar ~= nil,           true)
check("said as neuron, because it is not what a person said",
    scar and scar.marker,                                            "neuron")
-- }}}

-- {{{ what the model gets is the rebuilt one
-- The only reader whose output is spent. What a person sees costs nothing.
local messages = Transcript.messages(HANDLE, id)

local said = {}
for _, m in ipairs(messages) do
    if type(m.content) == "string" then table.insert(said, m.content) end
end

check("the folded exchange is gone from what is sent",
    table.concat(said, " "):find("Four kinds", 1, true),                   nil)
check("and the question after it is still there",
    table.concat(said, " "):find("spawn three of the first", 1, true) ~= nil,
                                                                         true)
-- }}}

-- {{{ replay is from the start, so order in the log decides
-- drop then keep is kept; keep then drop is dropped. If the state were stored
-- rather than derived, the second of each pair would have nothing to act on.
Transcript.prune(HANDLE, id, "drop", { 5 }, nil, "first")
Transcript.prune(HANDLE, id, "keep", { 5 }, nil, "second")
check("the last word wins",                Transcript.edits(HANDLE, id)[5], nil)

Transcript.prune(HANDLE, id, "keep", { 4 }, nil, "first")
Transcript.prune(HANDLE, id, "drop", { 4 }, nil, "second")
check("in the other direction too",
    Transcript.edits(HANDLE, id)[4].state,                           "dropped")
-- }}}

-- {{{ an edit has to name something
check("an edit with no atoms is refused",
    Transcript.prune(HANDLE, id, "drop", {}, nil, "nothing"),             nil)
check("and an invented verb is an error",
    pcall(Transcript.prune, HANDLE, id, "burn", { 1 }),                 false)
-- }}}

-- {{{ forgetting is not itself remembered
-- If the act of forgetting were replayed, the whole mechanism would be absurd:
-- every deletion would add a tool call and a result to the context, so
-- shortening a conversation would make it longer.
local other = "2026-09-06/140000-cafe"

Transcript.begin(HANDLE, other, { vocabulary = "asking", profile = "vanilla",
                                  system = "You configure things." })
Transcript.append(HANDLE, other, "you",    "list the source files")
Transcript.append(HANDLE, other, "tool",   "", "source_list")
Transcript.append(HANDLE, other, "result", "a very long listing indeed")
Transcript.append(HANDLE, other, "neuron", "There are many.")
Transcript.append(HANDLE, other, "tool",   "quote=the listing", "memory_forget")
Transcript.append(HANDLE, other, "result", "Forgotten. 26 characters.")

local kept_in_record = Transcript.blocks(HANDLE, other)
local sent           = Transcript.rebuild(HANDLE, other)

check("the record keeps the act of forgetting",   #kept_in_record,          7)
check("what is sent does not",                            #sent,           5)

local mentions = 0
for _, block in ipairs(sent) do
    if (block.name or ""):find("forget")
       or (block.text or ""):find("Forgotten", 1, true) then
        mentions = mentions + 1
    end
end
check("not the call, and not its answer either",       mentions,            0)
-- }}}

-- {{{ a result is never orphaned by that
-- A tool_result with no tool_use is rejected outright, so skipping a call has
-- to take its answer with it.
local calls, results = 0, 0
for _, block in ipairs(sent) do
    if block.marker == "tool"   then calls   = calls   + 1 end
    if block.marker == "result" then results = results + 1 end
end
check("one call left",                                    calls,            1)
check("and one answer for it",                          results,            1)
-- }}}

os.execute("rm -rf '" .. WORK .. "'")

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
