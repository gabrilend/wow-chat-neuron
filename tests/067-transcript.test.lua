--------------------------------------------------------------------------------
-- 067-transcript.test.lua
--
-- A conversation split across two files must read back as one conversation.
--
-- The split is by AUDIENCE: what people said in one file, what the machinery
-- said in the other. Everything here is about the seam between them -- that
-- merging restores the original order, that either half stands alone, and that
-- a conversation written before the split still opens.
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

-- A scratch root, so nothing here touches a real conversation.
local WORK = "/tmp/claude-1000/-mnt-mtwo-games-azeroth-core-wow-chat-neuron/"
          .. "bedafefb-6053-4b5b-b904-cb058c036837/scratchpad/transcript-test"
os.execute("rm -rf '" .. WORK .. "'")
os.execute("mkdir -p '" .. WORK .. "/logs/asking'")

local HANDLE = { neuron_root = WORK }

-- {{{ everything its callers reach for is still exported
-- WHY: an edit removed Transcript.new_id and every test here still passed,
-- because the tests name their own conversations. The menu did not -- opening
-- a conversation answered "attempt to call field 'new_id' (a nil value)".
-- Tests that only exercise what they set up cannot notice a missing door.
for _, name in ipairs({ "path", "new_id", "split", "begin", "append",
                        "blocks", "messages", "summary", "list", "read",
                        "stitched", "said", "human", "atoms", "prune",
                        "edits", "rebuild", "edits_path" }) do
    check("Transcript." .. name .. " exists",  type(Transcript[name]), "function")
end
-- }}}

-- {{{ a conversation, written the way one actually is
local id = "2026-09-06/120000-abcd"

Transcript.begin(HANDLE, id, { vocabulary = "world", profile = "vanilla",
                               system = "You operate a world." })

Transcript.append(HANDLE, id, "neuron", "@ this window\n\nWaiting.", "faq")
Transcript.append(HANDLE, id, "you",    "make me some undead")
Transcript.append(HANDLE, id, "neuron", "Looking that up.")
Transcript.append(HANDLE, id, "tool",   "type=undead  level=12", "world_creatures")
Transcript.append(HANDLE, id, "result", "entry  name\n299    Ghoul")
Transcript.append(HANDLE, id, "neuron", "Four kinds are usable.")
-- }}}

-- {{{ the two files exist, and hold the right halves
check("it is a split conversation",   Transcript.split(HANDLE, id),       true)

local human  = Transcript.read(HANDLE, id, "human")
local robots = Transcript.read(HANDLE, id, "robots")

check("what people said is in the human half",
    human:find("make me some undead", 1, true) ~= nil,                    true)
check("so is the call it made",
    human:find("[tool] world_creatures", 1, true) ~= nil,                 true)
check("the instructions are NOT",
    human:find("You operate a world", 1, true),                            nil)
check("nor is the answer that call gave",
    human:find("299    Ghoul", 1, true),                                   nil)

check("the instructions are in the robots half",
    robots:find("You operate a world", 1, true) ~= nil,                   true)
check("with the call's answer",
    robots:find("299    Ghoul", 1, true) ~= nil,                          true)
check("and nothing anybody said",
    robots:find("make me some undead", 1, true),                           nil)
-- }}}

-- {{{ both halves carry the header
-- Either file can be opened alone by somebody who has no idea the other
-- exists, and a file that cannot say which conversation it belongs to is one
-- that gets deleted by somebody tidying up.
check("the human half names the conversation",
    human:find(id, 1, true) ~= nil,                                       true)
check("so does the robots half",
    robots:find(id, 1, true) ~= nil,                                      true)
-- }}}

-- {{{ each half points at where the other picks up
check("the human half says where the machine's part goes",
    human:find("[from_robots]", 1, true) ~= nil,                          true)
check("and the robots half says where the conversation resumes",
    robots:find("[from_conversation]", 1, true) ~= nil,                   true)
-- }}}

-- {{{ merged, it is the conversation that happened, in order
local blocks = Transcript.blocks(HANDLE, id)

local order = {}
for _, block in ipairs(blocks) do table.insert(order, block.marker) end

check("every block comes back",                    #blocks,                 7)
check("the instructions first",                    order[1],         "system")
check("then the opening",                          order[2],         "neuron")
check("then the question",                         order[3],            "you")
check("then the sentence before the call",         order[4],         "neuron")
check("then the call",                             order[5],           "tool")
check("then its answer",                           order[6],         "result")
check("then the sentence after it",                order[7],         "neuron")
-- }}}

-- {{{ a section is a maximal run, not one per block
-- The three human blocks between the system prompt and the result are one
-- section. Numbering them separately would stop the sections alternating, and
-- a pointer would no longer name exactly one section on the other side.
check("the opening, question, sentence and call share a section",
    blocks[2].section == blocks[3].section
        and blocks[3].section == blocks[4].section
        and blocks[4].section == blocks[5].section,                       true)

check("the instructions are section zero",         blocks[1].section,       0)
check("the conversation is section one",           blocks[2].section,       1)
check("the result is section two",                 blocks[6].section,       2)
check("and the sentence after it is section three", blocks[7].section,      3)
-- }}}

-- {{{ one half alone
-- The opening, the question, the sentence before the call, the call, and the
-- sentence after it. Five -- the two that are missing are the instructions and
-- the call's answer, which are the machine's half.
local said_only = Transcript.blocks(HANDLE, id, "human")
check("the human half has five blocks",            #said_only,              5)

local text = Transcript.said(HANDLE, id)
check("what people said leaves the call out",
    text:find("world_creatures", 1, true),                                 nil)
check("and keeps the question",
    text:find("make me some undead", 1, true) ~= nil,                     true)
check("and the answer",
    text:find("Four kinds are usable", 1, true) ~= nil,                   true)
-- }}}

-- {{{ the model sees what it saw before
-- The opening is NOT sent, at all.
--
-- It is the FAQ: a page of shell commands for setting up keys and starting
-- ollama, written for somebody at a terminal. Handing it to a model bought one
-- thing -- an opening already on screen, so it would not greet twice -- and
-- cost several: llama3.2 read the commands as instructions and echoed
-- `$EDITOR .../secrets.conf` back as though it had done something.
--
-- It stays in the transcript, drawn with the FAQ's own formatting, where it is
-- exactly what it looks like: a note to the reader.
local messages = Transcript.messages(HANDLE, id)

check("the opening is not in what is sent",
    (function()
        for _, m in ipairs(messages) do
            local text = type(m.content) == "string" and m.content or ""
            if text:find("@ this window", 1, true) then return true end
        end
        return false
    end)(),                                                             false)

check("and a person speaks first",                 messages[1].role,    "user")

check("the question is that first turn",           messages[1].role,    "user")
check("with what was asked",   messages[1].content,   "make me some undead")

-- The tool call and its answer are rebuilt as the block pair the API wants.
local assistant = messages[2]
check("the call rides on an assistant turn",  assistant.role,     "assistant")
check("as a tool_use block",           assistant.content[2].type,   "tool_use")
check("naming the word",               assistant.content[2].name,
                                                          "world_creatures")

-- The bug this pattern used to have: two arguments on one line came back as
-- one argument whose value swallowed the rest of the line.
check("with the first argument",  assistant.content[2].input.type,   "undead")
check("AND the second",           assistant.content[2].input.level,      "12")
-- }}}

-- {{{ a conversation from before the split still opens
local old = "2026-09-06/110000-0000"
local old_path = Transcript.path(HANDLE, old)
os.execute("mkdir -p '" .. old_path:match("^(.*)/[^/]*$") .. "'")

local file = io.open(old_path, "w")
file:write("[system]\nold instructions\n\n[you]\nhello\n\n[neuron]\nhi\n\n")
file:close()

check("it is not a split conversation",     Transcript.split(HANDLE, old), false)

local old_blocks = Transcript.blocks(HANDLE, old)
check("and it is read whole, out of its one file",     #old_blocks,         3)
check("instructions included",                 old_blocks[1].marker, "system")

check("the listing says so, rather than saying nothing",
    Transcript.summary(HANDLE, old).old_format,                           true)
check("and does not say so about a split one",
    Transcript.summary(HANDLE, id).old_format,                           false)
-- }}}

-- {{{ the listing does not list machine halves as conversations
local listed = Transcript.list(HANDLE, 60)
check("two conversations, not four files",             #listed,             2)
-- }}}

-- {{{ a block with no home is an error, not a guess
-- Putting an unknown marker in the human half "just in case" is how the
-- machine's plumbing leaks back into the thing a person came to read.
check("an unknown kind of block is refused",
    pcall(Transcript.append, HANDLE, id, "invented", "x"),               false)
-- }}}

os.execute("rm -rf '" .. WORK .. "'")

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
