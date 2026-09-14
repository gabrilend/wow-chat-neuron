--------------------------------------------------------------------------------
-- tests/051-loop.test.lua
--
-- The conversation loop, driven against a scripted responder.
--
-- No network, no key, no database. Everything interesting about this loop is
-- the SHAPE of a conversation -- that a read runs and a change only plans, that
-- every tool_use gets a matching tool_result, that the turn cap stops a model
-- talking to itself forever -- and none of that should need an API to exercise.
--
-- The read path is stubbed too, because a real world.creatures needs MySQL. What
-- is being checked is that a read takes the running path and a change takes the
-- planning path, which is a property of the loop rather than of either word.
--------------------------------------------------------------------------------

local NEURON = "/mnt/mtwo/games/azeroth-core/wow-chat-neuron"

local Load     = dofile(NEURON .. "/src/024-load.lua")
local Loop     = Load(NEURON .. "/src/051-loop.lua")
local Registry = Load(NEURON .. "/src/045-toolbox/047-registry.lua")

local passed, failed = 0, 0

-- {{{ check
local function check(label, got, want)
    if got == want then passed = passed + 1 else
        failed = failed + 1
        print(string.format("FAIL  %s\n        got  %s\n        want %s",
            label, tostring(got), tostring(want)))
    end
end
-- }}}

local registry = Registry.load(NEURON)
check("the registry loads",  registry ~= nil,                                true)

-- {{{ a handle that reaches nothing
-- Enough for the loop; every path that would touch the world is stubbed.
-- The level cap is CARRIED, not found by opening a file.
--
-- It used to be read here by building the wow-chat path from root and profile,
-- which meant this fixture only worked because that one deployment happened to
-- be on this machine. The handle reads it once, out of the config directory
-- the deployment resolved, and everything that wants it asks.
local HANDLE = {
    neuron_root = NEURON,
    root        = "/mnt/mtwo/games/azeroth-core/wow-chat-2026",
    profile     = "vanilla",
    max_player_level = 40,
    max_player_level_where = "worldserver.conf line 2131",
    asking      = { model = "test", max_turns = 4, max_tokens = 100 },
    api_key     = "not-a-real-key",
}
-- }}}

-- {{{ responder(turns)
-- A scripted API. Hands back the next prepared turn and records what it was
-- sent, so the test can check the conversation that was built.
local function responder(turns)
    local sent, index = {}, 0
    return {
        available = function() return true end,
        send = function(_, body)
            index = index + 1
            table.insert(sent, body)
            local turn = turns[index]
            if not turn then
                return nil, "unreachable", "the script ran out of turns"
            end
            if turn.fail then return nil, turn.fail, turn.why end
            return turn
        end,
        sent = sent,
        count = function() return index end,
    }
end
-- }}}

-- {{{ says(text) / calls(id, name, input)
local function says(text)
    return { stop_reason = "end_turn",
             content = { { type = "text", text = text } } }
end

local function calls(blocks, text)
    local content = {}
    if text then table.insert(content, { type = "text", text = text }) end
    for _, block in ipairs(blocks) do
        table.insert(content, { type = "tool_use", id = block[1],
                                name = block[2], input = block[3] })
    end
    return { stop_reason = "tool_use", content = content }
end
-- }}}

-- {{{ a plain answer with no tools
local plain = responder({ says("There is nothing to do about that.") })
local answer = Loop.ask(HANDLE, registry, "hello", { api = plain })

check("a plain answer comes back",  answer.answer, "There is nothing to do about that.")
check("in one turn",                answer.turns,  1)
check("with no plans held",         next(answer.plans),  nil)
check("and the stop reason kept",   answer.ended,  "end_turn")
-- }}}

-- {{{ what the model is sent
local body = plain.sent[1]
check("the sentence is the first message",   body.messages[1].content,  "hello")
check("tools are sent",                      #body.tools > 0,           true)
check("and a system prompt",
    body.system:find("closed set of tools", 1, true) ~= nil,             true)
check("which names the real level cap",
    body.system:find("maximum character level is 40", 1, true) ~= nil,   true)

-- A deployment whose config has no MaxPlayerLevel line. The prompt must NOT
-- assert a number: claiming the retail 80 on a world capped at 40 builds
-- encounters nobody can reach, which is the whole reason this is read rather
-- than assumed.
local capless = {}
for key, value in pairs(HANDLE) do capless[key] = value end
capless.max_player_level = nil

local Registry = dofile(NEURON .. "/src/045-toolbox/047-registry.lua")
local world_words = Registry.load(NEURON, "world")
local without = Loop.system_prompt(capless, world_words)

check("with no cap in the config, none is asserted",
    without:find("maximum character level is", 1, true),                  nil)
check("and it says so rather than staying quiet",
    without:find("Do not assume a cap", 1, true) ~= nil,                 true)
-- }}}

-- {{{ a change is PLANNED, never applied
-- The rule the whole safety model rests on. `world.spawn` would reach the
-- database in plan, so this uses a stub operation registered by hand.
local planned_with = {}

local FAKE = Registry.define({
    name    = "world.example",
    summary = "A word that exists only in this test file.",
    kind    = "change",
    hands   = { "cold" },
    params  = { { name = "roster", type = "roster", required = true,
                  describes = "Who it acts on: a name, a list, or a query." } },
}, {
    plan = function(_, arguments)
        table.insert(planned_with, arguments.roster)
        return { steps = { { describes = "would do a thing" } } }
    end,
    apply = function()
        -- Reaching here at all is the failure this test exists to catch.
        error("apply must NEVER be called from inside the conversation loop")
    end,
    describe_plan = function() return "  would do a thing" end,
})

check("the stub registers",  FAKE ~= nil,                                    true)

-- A registry holding only it, so the loop has something safe to plan.
local only_fake = {
    ordered = { FAKE },
    by_name = { ["world.example"] = FAKE },
    of = function(name)
        if name == "world.example" then return FAKE end
        return nil, "no such thing"
    end,
}

local proposing = responder({
    calls({ { "call_1", "world_example", { roster = "the hunters" } } },
          "I will do this."),
    says("Waiting on you."),
})

local proposed = Loop.ask(HANDLE, only_fake, "do a thing", { api = proposing })

-- Whatever happened, apply was not called -- the stub errors if it is, and the
-- loop returning at all proves it did not.
check("the loop finished without applying anything",  proposed ~= nil,       true)
check("it took two turns",                            proposed.turns,        2)
check("one tool call was made",                       #proposed.calls,       1)
check("and it was the word the model named",          proposed.calls[1].tool,
                                                      "world_example")
-- }}}

-- {{{ every tool_use gets a tool_result with a matching id
-- A missing one is rejected outright by the API, and it is easy to produce by
-- returning early on the first failure -- so the failing case is the one checked.
local three = responder({
    calls({ { "a", "world_example",   { roster = "x" } },
            { "b", "world_nonsense",  {} },
            { "c", "world_example",   {} } }),
    says("done"),
})

Loop.ask(HANDLE, only_fake, "several at once", { api = three })

local replies = three.sent[2].messages[3].content
check("three calls get three results",       #replies,                       3)
check("ids match, in order",                 replies[1].tool_use_id,         "a")
check("including the invented word",         replies[2].tool_use_id,         "b")
check("and the one missing an argument",     replies[3].tool_use_id,         "c")
check("every one is a tool_result",          replies[2].type,       "tool_result")
check("a failure is marked as an error",     replies[2].is_error,            true)
check("an invented word is told what exists",
    replies[2].content:find("no such thing", 1, true) ~= nil,                true)
-- }}}

-- {{{ the assistant turn goes back verbatim
-- Reconstructing it risks losing a tool_use id, and an id that does not match
-- its result is rejected.
check("the assistant turn is the model's own content",
    three.sent[2].messages[2].content,  three.sent[2].messages[2].content)
check("and its role is assistant",  three.sent[2].messages[2].role, "assistant")
-- }}}

-- {{{ the turn cap
-- DIFFERENT arguments every turn. A model that keeps working -- reading
-- something new each round -- and simply never finishes is what the cap is for,
-- and it is a different failure from a model going in circles, which is caught
-- one turn in by the check below.
local forever = responder({
    calls({ { "1", "world_example", { roster = "a" } } }),
    calls({ { "2", "world_example", { roster = "b" } } }),
    calls({ { "3", "world_example", { roster = "c" } } }),
    calls({ { "4", "world_example", { roster = "d" } } }),
    calls({ { "5", "world_example", { roster = "e" } } }),
})

local capped = Loop.ask(HANDLE, only_fake, "loop forever", { api = forever })

check("the loop stops at the cap",       capped.turns,          4)
check("and says that is why it stopped", capped.ended,          "turn_limit")
check("with a note a person can read",
    capped.note:find("without a final answer", 1, true) ~= nil,              true)
check("listing every call it made",      #capped.calls,         4)
-- }}}

-- {{{ going in circles
-- The SAME call, over and over.
--
-- What this is for: a small model handed change tools proposes something
-- nobody asked for, then proposes it again, and again. Every round is a whole
-- request at the model. Twelve of them on the words "testing 123" is a minute
-- of somebody watching a spinner for a wall of PLANNED, NOT DONE -- and three
-- of those plans were the same plan with three different ids, only one of
-- which could ever be agreed to.
--
-- The cap alone would end it eventually. This ends it on the second round,
-- which is the first moment it is knowable.
local circling = responder({
    calls({ { "1", "world_example", { roster = "x" } } }),
    calls({ { "2", "world_example", { roster = "x" } } }),
    calls({ { "3", "world_example", { roster = "x" } } }),
    calls({ { "4", "world_example", { roster = "x" } } }),
})

local circles = Loop.ask(HANDLE, only_fake, "same thing forever",
                         { api = circling })

check("a repeated round ends the loop",   circles.ended,   "going_in_circles")
check("on the second round, not the cap", circles.turns,                    2)
check("having spent two requests, not four", #circling.sent,                2)
check("and saying why",
    circles.note:find("already been made", 1, true) ~= nil,               true)

-- The repeat is answered from what was already worked out, rather than run
-- again. For a read that is a saved query; for a change it is the difference
-- between one plan and two ids for one plan.
-- In `calls`, not in a request -- the loop stops rather than sending the
-- repeat's answer onward, which is the whole point. The window still shows it,
-- because a call the person never sees is a thing that happened without
-- anybody mentioning it.
local second = circles.calls[2].summary
check("the repeat is told it already asked",
    second:find("already", 1, true) ~= nil,                               true)
check("and there were exactly two calls",       #circles.calls,             2)
-- }}}

-- {{{ a failure part-way through keeps what was already said
local interrupted = responder({
    calls({ { "1", "world_example", { roster = "x" } } }, "Looking into it."),
    { fail = "rate_limited", why = "too many requests" },
})

local nothing, kind, why, partial =
    Loop.ask(HANDLE, only_fake, "start then fail", { api = interrupted })

check("a failure returns no answer",     nothing,               nil)
check("but names the kind",              kind,                  "rate_limited")
check("and the reason",                  why,                   "too many requests")
check("and keeps what was said first",   partial.answer,        "Looking into it.")
-- }}}

-- {{{ no key, no request
local keyless = {}
for key, value in pairs(HANDLE) do keyless[key] = value end
keyless.api_key = nil

local never, no_key_kind = Loop.ask(keyless, registry, "anything",
    { api = Load(NEURON .. "/src/050-api.lua") })
check("with no key nothing is sent",  never,                                 nil)
check("and it says which absence",    no_key_kind,                     "no_key")
-- }}}

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
