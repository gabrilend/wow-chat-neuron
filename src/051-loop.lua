--------------------------------------------------------------------------------
-- 051-loop.lua
--
-- A sentence in, a plan or an answer out.
--
-- The middle of the pipeline, and the last piece of it. A sentence already
-- reaches the server (059-menu.lua), the vocabulary already renders as
-- tools (048-schema.lua), operations are already enumerable (047-registry.lua),
-- and mechanisms already carry a step to the world (034-mechanism.lua). Between
-- the sentence and the tool call there was nothing.
--
-- THE RULE THE WHOLE SAFETY MODEL RESTS ON: inside this loop, a change is
-- PLANNED and never applied. When the model calls a word that alters anything,
-- the loop runs its plan and hands back the plan's description as the tool
-- result. So the model can compose freely -- twenty spawns, a teleport, a level
-- change -- and what reaches the person is twenty readable lines and a
-- question. The apply happens afterwards, through the door's hold-and-confirm,
-- which already exists and already refuses to confirm the same plan twice.
--
-- A model that could apply directly would be a model that could finish before
-- anybody read what it was doing.
--
-- READS RUN IMMEDIATELY, because there is nothing to agree to. That asymmetry
-- is what makes a request like "successive undead encounters, level
-- progressing" possible at all: the model has to LOOK several times while
-- composing, and stopping to ask permission to look would make the whole thing
-- unusable. It is the `kind` enum doing real work -- read and change take
-- different paths, decided by data on the declaration rather than by a list of
-- exceptions kept somewhere else.
--------------------------------------------------------------------------------

local Loop = {}

-- {{{ sibling(neuron_root, filename)
local function sibling(neuron_root, filename)
    return dofile(neuron_root .. "/src/" .. filename)
end
-- }}}

-- {{{ Loop.level_cap(handle)
-- What "max level" actually is here, read from the deployment rather than
-- assumed.
--
-- This is the single most load-bearing fact in the system prompt. A model that
-- does not know the cap is 40 will happily build an encounter chain up to 80,
-- and every step past the cap is an encounter nobody can reach.
--
-- It was briefly a table of profile names to numbers, which was wrong twice
-- over: the active profile here is `neuron`, which was not in the table, and
-- the lookup fell through to 80 -- producing the sentence "the maximum level is
-- 80, not 80" and, much worse, a confident claim that happened to be false. Per
-- the standing position that a fallback is a warning and a warning is an error,
-- there is now no fallback: the cap is read from the worldserver's own config
-- or it is not claimed at all.
--
-- Returns: cap, where it was read from -- or nil, why it could not be found.
function Loop.level_cap(handle)
    -- ASKED OF THE HANDLE, not found by rebuilding a path.
    --
    -- This used to construct `<root>/installed-files-<profile>/etc/
    -- worldserver.conf` itself and scan it. That is the wow-chat layout
    -- convention written out a second time, in a file that has nothing to do
    -- with deployment layout -- so on any deployment shaped differently, the
    -- menu would locate the config perfectly well while this kept looking in
    -- the wow-chat place and reported the cap unreadable from a deployment
    -- where it is plainly there.
    --
    -- The config directory shown in the menu is the authority. Anything that
    -- wants a server setting asks for it.
    if handle.max_player_level then
        return handle.max_player_level, handle.max_player_level_where
    end

    -- A profile with databases and no installed server is a real arrangement,
    -- so this is a fact about the deployment rather than a fault. What must not
    -- happen is asserting 80 when it is 40, which builds encounters nobody can
    -- reach.
    return nil, string.format(
        "%s/worldserver.conf has no MaxPlayerLevel line, so the level cap is\n"
     .. "  unknown. The setting is written by the deployment's config patches at\n"
     .. "  install time; a config without it is one that was generated and never\n"
     .. "  patched. The cap will not be asserted to the model.",
        tostring(handle.config_dir))
end
-- }}}

-- What the model is told before it chooses anything.
--
-- Deliberately short. Everything about what the operations DO is in the tool
-- schema, where it is generated from declarations and cannot drift; repeating
-- it here would create a second description that can disagree with the first.
-- What belongs here is only what the schema has nowhere to put: which world
-- this is, and what is unusual about it.
-- {{{ Loop.ASKING_PROMPT
-- What the configuration model is told.
--
-- It describes configuring a connection to a REMOTE inference service, because
-- that is what these levers do -- they set an endpoint, a model name, a
-- timeout. Nothing here says which endpoint is currently answering.
--
-- That omission is deliberate and it is not a lie. A model told it is running
-- locally starts reasoning about its own limits, offers to attempt less, and
-- treats the configuration as being about itself. One that believes it is
-- setting up a pipe for somebody else sets up the pipe. The job is the same
-- either way; only the framing differs, and one framing does it better.
Loop.ASKING_PROMPT = table.concat({
    "You configure how an application reaches a remote inference service. You "
 .. "are not operating that service and you are not the model it will reach -- "
 .. "you are setting up the connection to it.",

    "Your whole vocabulary is in the tools you have been given: read the "
 .. "configuration, change the endpoint, change the model name, change the "
 .. "timeout, and send one trivial request to see whether it answers. There is "
 .. "nothing else you can do and nothing else you should offer.",

    "You cannot see the world this application operates -- no characters, no "
 .. "creatures, no places. Requests about any of those belong in a different "
 .. "conversation; say so and stop.",

    "A change to the configuration comes back to you as a PLAN. Nothing has "
 .. "happened until a person agrees to it. Say what you propose; do not claim "
 .. "you have done it.",

    -- The instruction that was missing, and its absence cost twelve rounds of
    -- tool calls on the word "testing 123". A small model handed a set of
    -- change tools treats having them as a reason to use them: it proposed a
    -- new endpoint, a new model name and a shorter timeout, none of which
    -- anybody had mentioned, then proposed the same three again, and ran out of
    -- turns before saying a sentence. Nothing was applied -- the plan/apply
    -- split held -- but seven plans were waiting for agreement to changes
    -- nobody had asked for.
    "DO NOT CHANGE ANYTHING UNLESS YOU ARE ASKED TO. A greeting, a question, or "
 .. "a test message gets a sentence back and no tool calls at all. Propose a "
 .. "change only when the person has named the thing they want changed. Do not "
 .. "propose a change to demonstrate that you can.",

    "Never make the same proposal twice. If you have already proposed "
 .. "something, it is waiting -- say so and stop rather than proposing it "
 .. "again.",

    "After changing an endpoint or a model, run the check ONCE. A configuration "
 .. "that was accepted and does not work is the failure this exists to prevent.",

    "When you have said what you have to say, stop. Silence is a complete "
 .. "answer to \"hello\".",

    "Be brief. The person reading you is looking at a small window.",
}, "\n\n")
-- }}}

-- {{{ Loop.HOW_TO_CALL
-- How to write a tool call, with worked examples.
--
-- WHY THIS EXISTS AT ALL: a tool call has never been anything but text. The
-- model emits characters, the harness watches for an agreed shape and lifts it
-- out. Servers with "native" tool calling do exactly that and hand back the
-- result in a separate field -- the parsing moved, it did not vanish.
--
-- A small model has usually READ that shape without having been TRAINED to
-- emit it on cue. Asked to change a timeout it writes "I will change the
-- timeout to 15 seconds" -- a sentence describing the act instead of the act.
-- That is not disobedience and telling it off does not fix it: it does not
-- know what the act looks like from the inside.
--
-- So it is shown. Four examples, each adding one thing: no arguments, one
-- argument, several, then a call whose answer decides the next call. The shape
-- taught is exactly the one 056-dialects.lua lifts out of prose, so a model
-- that follows this is understood whether or not its server supports tool
-- calling at all.
--
-- Sent only where it earns its tokens -- see system_prompt. A model with a real
-- tool protocol should use that protocol, and teaching it a text form invites
-- it to answer in prose that merely LOOKS like a call.
Loop.HOW_TO_CALL = table.concat({
    "HOW TO CALL A TOOL.",

    "Writing a sentence about what you are going to do does not do it. "
 .. "\"I will change the timeout to 15 seconds\" changes nothing, and nobody "
 .. "sees a proposal. To act, write a JSON object on a line of its own, with "
 .. "exactly two keys: `name`, the tool's name, and `arguments`, an object of "
 .. "its parameters. Nothing else on that line.",

    "One: a tool that takes nothing.\n"
 .. '{"name": "asking_status", "arguments": {}}',

    "Two: one argument. The value's type is whatever the tool's schema says -- "
 .. "a number is bare, a string is quoted.\n"
 .. '{"name": "asking_timeout", "arguments": {"seconds": 15}}',

    "Three: several arguments, in any order.\n"
 .. '{"name": "world_spawn", "arguments": {"creature": 299, '
 .. '"place": "goldshire", "count": 3}}',

    "Four: a call whose answer decides the next one. Write ONE call, stop, and "
 .. "wait -- the answer comes back to you as a tool result and you may then "
 .. "write another. Do not guess what a call would have returned and carry on "
 .. "as though you had seen it.\n"
 .. '{"name": "world_creatures", "arguments": {"type": "undead", "level": 12}}',

    "You may write a sentence before or after the object; the object is what "
 .. "gets run. If you are not calling anything, write no object at all.",
}, "\n\n")
-- }}}

-- {{{ Loop.local_model_answers(handle, registry)
-- Will a small local model be the one reading this prompt?
--
-- The configuration window always: it is the life raft, and a life raft that
-- needed the thing that is broken would not be one. Otherwise it depends on
-- what the configuration says answers.
--
-- Answered from FILES -- the config and whether a key exists -- and never by
-- reaching out. Building a system prompt should not depend on the network
-- being up.
function Loop.local_model_answers(handle, registry)
    if registry and registry.vocabulary == "asking" then return true end

    local asking = handle.asking
    if not asking or not asking.bench then return false end
    if asking.use == "bench" then return true end

    -- No key means the configured service cannot be reached whatever it says,
    -- so the bench is what will answer.
    local Keys = sibling(handle.neuron_root, "052-keys.lua")
    return not Keys.present(handle.api_key_path, "the API key")
end
-- }}}

-- {{{ Loop.system_prompt(handle, registry)
function Loop.system_prompt(handle, registry)
    local teach = Loop.local_model_answers(handle, registry)
        and ("\n\n" .. Loop.HOW_TO_CALL) or ""

    if registry.vocabulary == "asking" then
        return Loop.ASKING_PROMPT .. teach
    end

    local cap, source = Loop.level_cap(handle)

    -- Said only when it is known, and said differently when it is not. A prompt
    -- that asserts a cap it could not read is a prompt that will be wrong on
    -- exactly the deployments where being wrong matters.
    local about_level

    if cap then
        about_level = string.format(
            "This world's maximum character level is %d. The '%s' profile is "
         .. "active. Anything you build past level %d is unreachable, so do not "
         .. "assume the retail cap of 80.", cap, handle.profile, cap)
    else
        about_level =
            "The maximum character level of this world could not be read, and it "
         .. "is very likely NOT the retail 80 -- these profiles run caps of 20 "
         .. "and 40. Do not assume a cap. If a request depends on one, say so "
         .. "and ask."
    end

    return table.concat({
        "You are operating a World of Warcraft 3.3.5a private server through a "
     .. "closed set of tools. Everything you can do is in that set; there is no "
     .. "way to run SQL, run a command, or write code.",

        about_level,

        "The world is EMPTY by design. Almost nothing is spawned. When somebody "
     .. "asks for creatures, you are adding to an empty world rather than to an "
     .. "existing population, so you decide where things go.",

        "Before spawning anything, use world.creatures to find out what exists "
     .. "at the level you want. Creature entry numbers are not guessable and a "
     .. "wrong one is refused.",

        "Anything that changes the world comes back to you as a PLAN, not as a "
     .. "result. Nothing has happened yet. A person reads the plan and agrees to "
     .. "it. Say what you propose in plain language; do not claim you have done "
     .. "it.",

        "Do not change anything unless you are asked to. A greeting or a "
     .. "question gets a sentence back and no tool calls. Never make the same "
     .. "proposal twice -- if you have already proposed something it is "
     .. "waiting, so say so and stop.",

        "Be concrete and brief. The person reading you is looking at a chat "
     .. "window in a game, not a terminal.",
    }, "\n\n") .. teach
end
-- }}}

-- {{{ text_of(content)
-- The prose out of an assistant turn, ignoring the tool calls beside it.
local function text_of(content)
    local said = {}
    for _, block in ipairs(content or {}) do
        if block.type == "text" and block.text and block.text ~= "" then
            table.insert(said, block.text)
        end
    end
    return table.concat(said, "\n")
end
-- }}}

-- {{{ run_read(handle, operation, arguments)
local function run_read(handle, operation, arguments)
    -- The registry already holds the operation's functions; loading its file
    -- again here would be a second route to the same code, and a route that can
    -- disagree with the first the moment a registry entry is built any way but
    -- from a file.
    local answer, why = operation.run(handle, arguments)
    if not answer then
        return nil, why
    end

    return answer.describes or "done"
end
-- }}}

-- {{{ plan_change(handle, operation, arguments, hold)
-- Compute what would happen, keep it, and describe it.
--
-- The plan is HELD rather than recomputed later, because planning again could
-- produce something different -- ten minutes pass, somebody logs in, a creature
-- dies -- and agreeing to a description should run the thing that was
-- described. The hand-pulled levers in 068-conversations.lua work this way too;
-- this puts the model's proposals in the same store, so one confirm path runs
-- both.
local function plan_change(handle, operation, arguments, hold)
    local plan, why = operation.plan(handle, arguments)
    if not plan then
        return nil, why
    end

    local identifier = hold(plan, operation)

    local described = operation.describe_plan and operation.describe_plan(plan)
        or (plan.steps and (#plan.steps .. " steps") or "a plan")

    return string.format(
        "PLANNED, NOT DONE. Nothing has changed. This is waiting for the "
     .. "person to agree to it.\nPlan id: %s\n\n%s", identifier, described)
end
-- }}}

-- {{{ Loop.ask(handle, registry, sentence, options)
-- The whole thing.
--
-- Returns: { answer, plans, turns, calls } or nil plus a failure kind and text.
function Loop.ask(handle, registry, sentence, options)
    options = options or {}

    -- The transport is a seam rather than a hard import, so the loop can be
    -- driven against a scripted responder with no network and no key. Every
    -- interesting thing here -- the read/change split, tool_result id matching,
    -- the turn cap, a failure part-way through -- is about the SHAPE of a
    -- conversation, and none of it should need an API to exercise.
    local Api    = options.api or sibling(handle.neuron_root, "050-api.lua")
    local Schema = sibling(handle.neuron_root, "045-toolbox/048-schema.lua")

    local ready, kind, why = Api.available(handle)
    if not ready then return nil, kind, why end

    local tools  = Schema.tools(registry, options.filter)
    local system = Loop.system_prompt(handle, registry)

    -- THE TRANSCRIPT IS THE ONLY RECORD, and there used to be two.
    --
    -- A separate asking log wrote what was asked, what was offered and what
    -- came back into the same directory the transcripts live in, under its own
    -- id -- so `logs/asking/<date>/` held two unrelated files per conversation
    -- and the conversation lister had to scan and discard half of what it
    -- found.
    --
    -- Everything it held is in the transcript: the question, the answers, the
    -- calls, the results, and the system prompt as section zero. The one thing
    -- lost is the exact TOOL LIST offered at the time, which is reconstructed
    -- from the vocabulary the transcript names -- the same trade already made
    -- for the system prompt, and made the same way for the same reason.

    -- The conversation so far, plus what was just said.
    --
    -- This used to be only the new sentence, every time -- so the model had no
    -- memory of anything and each message was turn one of a fresh
    -- conversation. It could not follow through on something it had proposed
    -- one line earlier, could not be asked "do that", and produced a new asking
    -- log per message. Everything that looked like a small model being
    -- forgetful was this.
    local messages = {}
    for _, earlier in ipairs(options.history or {}) do
        table.insert(messages, earlier)
    end
    table.insert(messages, { role = "user", content = sentence })

    -- Where a plan goes when it is made. The door supplies its own store, so
    -- that a plan the model proposed is confirmed through exactly the same path
    -- as one the hand-matched vocabulary proposed -- one hold, one confirm, one
    -- place a plan can be run from. Without an outside store this keeps its own,
    -- which is what a test and the command line want.
    local kept = {}
    local hold = options.hold or function(plan, operation)
        local identifier = string.format("%s-%d-%d",
            operation.verb, os.time(), math.random(1000, 9999))
        kept[identifier] = { plan = plan, operation = operation, made = os.time() }
        return identifier
    end

    local said      = {}
    local calls     = {}
    local fell_back = nil

    -- {{{ signature_of(block)
    -- One string naming a tool call, so the same call made twice is
    -- recognisable as the same call.
    --
    -- The arguments are sorted before they are joined, because two calls with
    -- the same arguments in a different order are the same call, and a model
    -- that varies the order is not making a different request.
    local function signature_of(block, operation)
        local parts = {}
        for key, value in pairs(block.input or {}) do
            table.insert(parts, key .. "=" .. tostring(value))
        end
        table.sort(parts)
        return ((operation and operation.name) or block.name or "?")
            .. "(" .. table.concat(parts, ",") .. ")"
    end
    -- }}}

    -- What has already been asked for, and what came back.
    --
    -- WHY: a small model handed change tools will propose the same change over
    -- and over. "testing 123" produced twelve rounds of tool calls, seven
    -- plans, three of them literal duplicates of each other, and no sentence --
    -- and every round is a whole request at the model. The plan/apply split
    -- meant nothing was DONE, so this is not a safety hole; it is a loop that
    -- costs a minute and produces a wall of PLANNED, NOT DONE.
    --
    -- Answering a repeat with the earlier answer breaks the cycle where
    -- repeating it is most attractive: the model gets told the thing it wants
    -- already exists.
    local answered = {}
    local max_turns = (handle.asking and handle.asking.max_turns) or 12

    for turn = 1, max_turns do
        local response, failure, failure_why = Api.send(handle, {
            system   = system,
            messages = messages,
            tools    = tools,
            -- The configuration conversation runs on the local model when
            -- there is one. It is setting up a connection to a remote service;
            -- doing that on the remote service is both absurd and expensive.
            -- `only`, not `prefer`. The configuration window never reaches a
            -- remote service, whatever the configuration says.
            only     = (registry.vocabulary == "asking") and "bench" or nil,
        })

        if not response then
            -- Anything already said is kept. A conversation that produced three
            -- useful sentences and then hit a rate limit should show the three.
            return nil, failure, failure_why, { answer = table.concat(said, "\n"),
                                                plans = kept, turns = turn }
        end

        local spoken = text_of(response.content)
        if spoken ~= "" then table.insert(said, spoken) end

        -- Which server actually answered, said once and kept. A fallback that
        -- did not announce itself would make a frontier model's plan and a
        -- local one's plan look identical, and they are not remotely alike.
        if response.answered_by and response.answered_by ~= fell_back then
            fell_back = response.answered_by
            table.insert(said, 1, "[ " .. response.answered_by .. " ]")
        end


        if response.stop_reason ~= "tool_use" then
            -- The turn that ended it goes in as well, or the next question
            -- arrives with the model's own last answer missing from what it
            -- can see.
            table.insert(messages,
                { role = "assistant", content = response.content })

            local waiting = {}
            for identifier in pairs(kept) do table.insert(waiting, identifier) end
            table.sort(waiting)


            return {
                answer = table.concat(said, "\n"),
                plans  = kept,
                turns  = turn,
                history = messages,
                calls  = calls,
                ended  = response.stop_reason,
                via    = fell_back,
            }
        end

        -- The assistant turn goes back verbatim. Reconstructing it would risk
        -- losing a tool_use id, and an id that does not match its result is
        -- rejected outright.
        table.insert(messages, { role = "assistant", content = response.content })

        local results = {}

        -- How many of THIS turn's calls were ones already made. If all of them
        -- were, the model is going in a circle and another round will produce
        -- the same circle -- so the loop ends rather than spending the rest of
        -- its turn budget confirming that.
        local repeated = 0
        local asked_for = 0

        for _, block in ipairs(response.content or {}) do
            if block.type == "tool_use" then
                asked_for = asked_for + 1
                local operation, arguments = Schema.route(registry, block)

                local text, failed

                -- Named by the OPERATION where one was found, not by
                -- whatever the model typed. The same word arrives spelled two
                -- ways -- `asking_model` from a structured tool call,
                -- `asking.model` when a model that has no tool protocol speaks
                -- one as text -- and both route to the same operation. Keying
                -- on the spelling would let a model alternate between the two
                -- and never repeat itself.
                local signature = signature_of(block, operation)
                local earlier   = answered[signature]

                if earlier then
                    -- Already asked, already answered. Nothing runs and no
                    -- second plan is made -- a duplicate plan is two ids for
                    -- one change, and agreeing to one of them would leave the
                    -- other waiting forever.
                    repeated = repeated + 1
                    text, failed = earlier.text, earlier.failed

                    if earlier.planned then
                        text = string.format(
                            "You already proposed exactly this and it is "
                         .. "waiting as %s. It has not been applied and it has "
                         .. "not been forgotten. Do not propose it again -- "
                         .. "say what you are waiting for and stop.\n\n%s",
                            earlier.planned, earlier.text)
                    else
                        text = "You already made this exact call in this "
                            .. "conversation. The answer has not changed:\n\n"
                            .. earlier.text
                    end

                elseif not operation then
                    -- `arguments` is the refusal text here, and it carries the
                    -- near matches and the whole vocabulary -- the only thing
                    -- telling a model what does exist.
                    text, failed = arguments, true
                elseif operation.kind.runs_now then
                    -- The conversation this is being spoken in, supplied here
                    -- rather than asked of the model. It does not know its own
                    -- id, should not have to, and must not be able to get it
                    -- wrong -- a wrong id would edit somebody else's
                    -- conversation.
                    if operation.needs_conversation then
                        arguments.conversation = options.conversation
                    end

                    local answer, read_why = run_read(handle, operation, arguments)
                    text, failed = answer or read_why, answer == nil

                    -- A forget is not answered from memory on a repeat. Every
                    -- call is about a different atom by definition -- the one
                    -- it named last time is gone -- so the same quotation twice
                    -- is a real second question with a real second answer,
                    -- which is "there is nothing like that here any more".
                    if operation.kind.name ~= "internal" then
                        answered[signature] = { text = text, failed = failed }
                    end
                else
                    local described, plan_why =
                        plan_change(handle, operation, arguments, hold)
                    text, failed = described or plan_why, described == nil
                    answered[signature] = { text = text, failed = failed,
                        planned = described and described:match("Plan id: (%S+)") }
                end

                -- What the model actually asked for, kept so the window can
                -- show it. A tool call the person never sees is a thing that
                -- happened to their world without anybody mentioning it.
                local said_arguments = {}
                for key, value in pairs(block.input or {}) do
                    table.insert(said_arguments,
                        key .. "=" .. tostring(value):sub(1, 60))
                end
                table.sort(said_arguments)

                table.insert(calls, {
                    tool      = block.name,
                    arguments = table.concat(said_arguments, "  "),
                    ok        = not failed,
                    -- Not truncated. It was cut at 100 characters, which
                    -- ended mid-word ("the remote service this window co") and
                    -- made a complete answer look like a broken one.
                    summary   = (text or ""),
                })




                -- EVERY tool_use gets a tool_result with a matching id, even
                -- the ones that failed. A missing one is rejected by the API,
                -- and it is easy to produce by returning early on the first
                -- failure.
                table.insert(results, {
                    type        = "tool_result",
                    tool_use_id = block.id,
                    content     = text or "the operation returned nothing at all",
                    is_error    = failed or nil,
                })
            end
        end

        table.insert(messages, { role = "user", content = results })

        -- Every call this turn was one already made. Stop.
        --
        -- The turn cap alone would catch this eventually, at twelve rounds and
        -- a minute of somebody watching a spinner. This catches it on the
        -- second, which is the first moment it is knowable.
        if asked_for > 0 and repeated == asked_for then
            local waiting = {}
            for identifier in pairs(kept) do table.insert(waiting, identifier) end
            table.sort(waiting)


            return {
                answer = table.concat(said, "\n"),
                plans  = kept,
                turns  = turn,
                history = messages,
                calls  = calls,
                ended  = "going_in_circles",
                via    = fell_back,
                note   = string.format(
                    "Stopped: every one of the %d calls in that round had "
                 .. "already been made and answered, so another round would "
                 .. "produce the same round. Nothing was applied. What is "
                 .. "above is everything that was said.", asked_for),
            }
        end
    end

    -- The cap. Reached means the model kept calling tools without finishing,
    -- which is usually a loop: a read, a refusal, the same read again.
    local waiting = {}
    for identifier in pairs(kept) do table.insert(waiting, identifier) end
    table.sort(waiting)


    return {
        answer = table.concat(said, "\n"),
        plans  = kept,
        turns  = max_turns,
        history = messages,
        calls  = calls,
        ended  = "turn_limit",
        via    = fell_back,
        note   = string.format(
            "Stopped after %d rounds of tool calls without a final answer. "
         .. "What is above is everything that was said and every plan that was "
         .. "made; none of it has been applied. This usually means the model "
         .. "repeated a call that kept failing -- the calls are listed so you "
         .. "can see which.", max_turns),
    }
end
-- }}}

return Loop
