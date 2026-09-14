--------------------------------------------------------------------------------
-- 068-conversations.lua
--
-- Many conversations, one port, each revived from its own transcript.
--
-- WHY ONE PORT: a chat window used to be its own process on its own port, and
-- the second one wanted 7880, and the third 7881. Anything reachable from
-- outside this machine would then need a router opening a port per
-- conversation, which is not a thing anybody should be asked to do. So the menu
-- serves them all, addressed by an id rather than by a port number.
--
-- WHY REVIVED RATHER THAN HELD: with no process per conversation there is
-- nowhere for a running context to live, and that turns out to be the better
-- design rather than a consequence. The transcript is the conversation. To
-- answer, it is read back into messages, extended, and written again. A
-- refresh, a restart, a machine reboot, somebody else's browser -- all the same
-- thing, because none of them is the place the conversation lives.
--
-- The cost is re-reading a file per turn, which for a text file of a few
-- kilobytes is nothing next to waiting for a model.
--
-- The one thing that MUST stay in memory is a held plan: it is a computed
-- statement about the world at one moment, and a moment is not a thing to
-- write down and offer again tomorrow.
--------------------------------------------------------------------------------

local Conversations = {}

-- {{{ sibling
local function sibling(neuron_root, filename)
    return dofile(neuron_root .. "/src/" .. filename)
end
-- }}}

-- {{{ PLANS
-- Plans awaiting agreement, keyed by conversation. In memory on purpose: a plan
-- describes the world as it was when it was computed, and one that survived a
-- restart would be a description of a world that has moved on.
--
-- ONE TABLE PER PROCESS, not one per load, and this is the whole reason
-- agreeing to a plan never once worked.
--
-- `sibling` loads with dofile, which RE-EXECUTES the file. The menu loads this
-- module inside the request that handles a route -- so the copy that computed
-- a plan and put it here was thrown away when that request finished, and the
-- next request built a fresh module with an empty table. Every apply came back
-- with "that plan is no longer available", which is a true sentence about the
-- wrong thing: the plan had not expired, it had never been anywhere the second
-- request could see.
--
-- package.loaded is the runtime's own one-per-process table and is what
-- 024-load.lua uses for exactly this reason. The same file loaded ten times
-- reaches the same plans.
local PLANS_KEY = "neuron.plans"

if not package.loaded[PLANS_KEY] then
    package.loaded[PLANS_KEY] = { plans = {}, sequence = 0 }
end

local KEPT  = package.loaded[PLANS_KEY]
local PLANS = KEPT.plans
-- }}}

-- {{{ Conversations.opening(handle, vocabulary)
-- The first thing in a conversation, before anybody has said anything.
--
-- WHY IT IS A REAL TURN AND NOT PAGE DECORATION: it used to be drawn by the
-- chat page and nowhere else, which meant the person saw it and the model did
-- not. A model opening on an empty window has nothing to be about, and a small
-- one handed a set of change tools treats that emptiness as an invitation --
-- "testing 123" came back with seven proposals to change an endpoint, a model
-- name and a timeout that nobody had mentioned.
--
-- Written into the transcript as neuron's own first turn, it is the last thing
-- the model said before the person spoke. That is a very different starting
-- position: it has already opened the conversation, so the first message does
-- not have to be filled with something.
--
-- The formatting marks are the chat page's: "# " is a question, "@ " a
-- right-justified heading, "---" a rule. They survive into the model's context
-- as plain text, which costs nothing and reads fine.
--
-- Returns a list of lines, or nil when a vocabulary has no opening.
function Conversations.opening(handle, vocabulary)
    if vocabulary == "asking" then
        local root = handle.neuron_root
        return {
            "@ while the local model loads",
            "",
            "# set the model's API key",
            "  rm -f " .. root .. "/secrets/api.key",
            "  touch " .. root .. "/secrets/api.key",
            "  chmod 600 " .. root .. "/secrets/api.key",
            "  printf %s 'sk-ant-...' > " .. root .. "/secrets/api.key",
            "",
            "# set the game master password",
            "  touch " .. root .. "/secrets/soap.key",
            "  chmod 600 " .. root .. "/secrets/soap.key",
            "  printf %s 'the-password' > " .. root .. "/secrets/soap.key",
            "",
            "# set the database password (it belongs to the deployment)",
            "  $EDITOR " .. tostring(handle.root) .. "/secrets.conf",
            "",
            "# start the local model",
            "  ollama serve",
            "  ollama list",
            "  ollama pull qwen2.5",
            "",
            "---",
            "",
            "Nothing above has been done. Wait for the person to say what they "
         .. "want changed.",
        }
    end

    -- The world window. Shorter, because its vocabulary is listed beside it and
    -- repeating a list that is generated from declarations is how the two come
    -- to disagree.
    local Loop = sibling(handle.neuron_root, "051-loop.lua")
    local cap  = Loop.level_cap(handle)

    return {
        "@ this window",
        "",
        (handle.profile
            and ("Pointed at the '" .. handle.profile .. "' profile")
            or  "Pointed at this world")
            .. (cap and (", where the maximum character level is " .. cap) or "")
            .. ".",
        "",
        "The world is empty by design. Anything that changes it is PROPOSED "
     .. "here and applied only after somebody agrees.",
        "",
        "---",
        "",
        "Waiting. Nothing happens until the person asks for something.",
    }
end
-- }}}

-- {{{ Conversations.open(handle, vocabulary)
-- A new conversation. Returns its id.
function Conversations.open(handle, vocabulary)
    local Transcript = sibling(handle.neuron_root, "067-transcript.lua")
    local Registry   = sibling(handle.neuron_root, "045-toolbox/047-registry.lua")
    local Loop       = sibling(handle.neuron_root, "051-loop.lua")

    local id = Transcript.new_id()

    -- The instructions are written into the file at the start, so a revived
    -- conversation is governed by the prompt it was begun under rather than
    -- whatever the code says today. A conversation that changes its own rules
    -- when the software is updated is a conversation nobody can reason about.
    local registry = Registry.load(handle.neuron_root, vocabulary or "world")

    Transcript.begin(handle, id, {
        vocabulary = vocabulary or "world",
        profile    = handle.profile,
        system     = registry and Loop.system_prompt(handle, registry) or nil,
    })

    -- Named `faq` so the chat page can draw it with the FAQ's own formatting
    -- rather than as a wall of assistant prose. The name rides on the marker
    -- line, which the transcript reader already carries through.
    local opening = Conversations.opening(handle, vocabulary or "world")
    if opening and #opening > 0 then
        Transcript.append(handle, id, "neuron",
            table.concat(opening, "\n"), "faq")
    end

    return id
end
-- }}}

-- {{{ Conversations.vocabulary_of(handle, id)
-- Which levers this conversation was opened with, read from its own header.
--
-- From the file rather than from a table in memory, so a conversation revived
-- next week reaches exactly what it reached when it began. A configuration
-- conversation must not quietly become a world one because the default changed.
function Conversations.vocabulary_of(handle, id)
    local Transcript = sibling(handle.neuron_root, "067-transcript.lua")
    local text = Transcript.read(handle, id)
    if not text then return nil end
    return text:match("levers%s+(%a+)") or "world"
end
-- }}}

-- {{{ Conversations.ask(handle, id, said)
-- One turn. Read the conversation, add to it, write it back.
function Conversations.ask(handle, id, said, prefer)
    local Transcript = sibling(handle.neuron_root, "067-transcript.lua")
    local Registry   = sibling(handle.neuron_root, "045-toolbox/047-registry.lua")
    local Loop       = sibling(handle.neuron_root, "051-loop.lua")
    local Api        = sibling(handle.neuron_root, "050-api.lua")

    local vocabulary = Conversations.vocabulary_of(handle, id)
    if not vocabulary then
        return { kind = "trouble", text = "There is no conversation " .. id .. "." }
    end

    -- Read the conversation BEFORE adding this turn to it, then add it.
    --
    -- The order used to be the other way round, and the question then appeared
    -- twice in what the model saw: once from the file it had just been written
    -- to, and once more because Loop.ask appends the sentence itself. A model
    -- asked the same thing twice in the same breath answers the second one,
    -- and every turn carried a spurious repeat of the last.
    --
    -- Written to the file immediately afterwards, so a loop that hangs or is
    -- killed still leaves the question somebody asked.
    local history = Transcript.messages(handle, id)

    Transcript.append(handle, id, "you", said)

    local registry, registry_why = Registry.load(handle.neuron_root, vocabulary)
    if not registry then
        return { kind = "trouble", text = registry_why }
    end

    local ready, _, why = Api.available(handle)
    if not ready and vocabulary ~= "asking" then
        return { kind = "trouble", text = why }
    end

    local answer, failure, failure_why, partial = Loop.ask(
        handle, registry, said, {
            history = history,
            -- Which conversation this is, for the levers that act on it rather
            -- than on the world. memory.forget is the only one today.
            conversation = id,
            -- Which model answers this turn.
            --
            -- A configuring conversation is local-only whatever anybody asks
            -- for: it is the window you open when nothing works, and one that
            -- could reach a paid service to ask how to reach a paid service is
            -- not a life raft. Everything else takes the caller's preference,
            -- which is what the continue dialog is choosing.
            only    = (vocabulary == "asking" and "bench")
                   or (prefer == "local" and "bench")
                   or nil,
            hold    = function(plan, operation)
                KEPT.sequence = KEPT.sequence + 1
                local identifier = "plan-" .. KEPT.sequence
                PLANS[id] = PLANS[id] or {}
                PLANS[id][identifier] = { plan = plan,
                                          operation = operation.name,
                                          made = os.time() }
                return identifier
            end,
        })

    -- {{{ write what was said, whatever the outcome
    -- A failed turn is still a turn that happened. Leaving it out means a
    -- revived conversation has a question nobody answered and no sign of why.
    local reached = answer or partial

    for _, call in ipairs((reached and reached.calls) or {}) do
        Transcript.append(handle, id, "tool",
            call.arguments ~= "" and call.arguments or "  (no arguments)",
            call.tool)
        Transcript.append(handle, id, "result", call.summary or "")
    end

    if reached and reached.answer and reached.answer ~= "" then
        Transcript.append(handle, id, "neuron", reached.answer)
    end
    -- }}}

    if not answer then
        Transcript.append(handle, id, "neuron",
            string.format("(%s) %s", tostring(failure), tostring(failure_why)))
        return { kind = "trouble",
                 text = string.format("(%s) %s", failure, failure_why),
                 calls = reached and reached.calls }
    end

    local waiting = {}
    for identifier in pairs(PLANS[id] or {}) do table.insert(waiting, identifier) end
    table.sort(waiting)

    return {
        kind        = #waiting > 0 and "plan" or "said",
        text        = answer.answer ~= "" and answer.answer or "Nothing to say.",
        plan        = waiting[1],
        plans       = waiting,
        calls       = answer.calls,
        answered_by = answer.via,
        note        = answer.note,
    }
end
-- }}}

-- {{{ Conversations.pull(handle, id, operation_name, arguments)
-- A lever pulled by hand, through the same path a tool call takes.
function Conversations.pull(handle, id, operation_name, arguments)
    local Transcript = sibling(handle.neuron_root, "067-transcript.lua")
    local Registry   = sibling(handle.neuron_root, "045-toolbox/047-registry.lua")

    local vocabulary = Conversations.vocabulary_of(handle, id)
    if not vocabulary then
        return { kind = "trouble", text = "There is no conversation " .. id .. "." }
    end

    local registry, registry_why = Registry.load(handle.neuron_root, vocabulary)
    if not registry then return { kind = "trouble", text = registry_why } end

    local operation, why = registry.of(operation_name)
    if not operation then return { kind = "trouble", text = why } end

    local given = {}
    local said = {}

    for _, parameter in ipairs(operation.params) do
        local value = (arguments or {})[parameter.name]

        if value ~= nil and value ~= "" then
            if parameter.type.name == "integer" then
                given[parameter.name] = math.floor(tonumber(value) or 0)
            elseif parameter.type.name == "number" then
                given[parameter.name] = tonumber(value)
            elseif parameter.type.name == "boolean" then
                given[parameter.name] = (value == true or value == "true"
                    or value == "yes" or value == "1")
            else
                given[parameter.name] = value
            end
            table.insert(said, parameter.name .. "=" .. tostring(value))
        elseif parameter.required then
            return { kind = "trouble", text = string.format(
                "%s needs %s.\n%s", operation.name, parameter.name,
                parameter.describes) }
        end
    end

    -- A lever pulled by hand goes into the transcript as what it was: the
    -- person acting directly. A conversation missing the acts taken during it
    -- is a conversation that cannot explain how the world got this way.
    Transcript.append(handle, id, "you",
        operation.name .. " " .. table.concat(said, " "))

    -- `runs_now` rather than a comparison against "read".
    --
    -- The kind says what the dispatcher must do; asking whether it is called
    -- "read" means every new kind that also runs immediately has to find every
    -- such comparison. `internal` -- memory.forget -- was the one that found
    -- this, by arriving here and looking for a `plan` it does not have.
    if operation.kind.runs_now then
        -- The conversation this was pulled in, for levers that act on it
        -- rather than on the world. Supplied here rather than asked for: the
        -- person pulling a lever by hand should not have to type an id they
        -- are already looking at.
        if operation.needs_conversation then given.conversation = id end

        local answer, read_why = operation.run(handle, given)
        local text = answer and (answer.describes or "done") or read_why

        -- ONE LINE, joined the way the loop joins them, because the tool
        -- line lives in the readable half and a call spread over five lines
        -- there is five lines of machinery in the middle of a conversation.
        -- Two spaces between arguments: that is the separator the reader
        -- splits on, and a single space can appear inside a value.
        Transcript.append(handle, id, "tool",
            table.concat(said, "  "), operation.name)
        Transcript.append(handle, id, "result", text)

        return { kind = answer and "said" or "trouble", text = text }
    end

    local plan, plan_why = operation.plan(handle, given)
    if not plan then
        Transcript.append(handle, id, "neuron", plan_why)
        return { kind = "trouble", text = plan_why }
    end

    KEPT.sequence = KEPT.sequence + 1
    local identifier = "plan-" .. KEPT.sequence
    PLANS[id] = PLANS[id] or {}
    PLANS[id][identifier] = { plan = plan, operation = operation.name,
                              made = os.time() }

    local described = operation.describe_plan and operation.describe_plan(plan)
        or (#(plan.steps or {}) .. " steps")

    Transcript.append(handle, id, "neuron", "PLANNED, NOT DONE.\n" .. described)

    return { kind = "plan", text = described, plan = identifier }
end
-- }}}

-- {{{ Conversations.apply(handle, id, plan_id)
-- Agree to a held plan and run it.
function Conversations.apply(handle, id, plan_id)
    local Transcript = sibling(handle.neuron_root, "067-transcript.lua")
    local Registry   = sibling(handle.neuron_root, "045-toolbox/047-registry.lua")
    local Liveness   = sibling(handle.neuron_root, "004-liveness.lua")
    local Receipts   = sibling(handle.neuron_root, "006-receipts.lua")

    local held = (PLANS[id] or {})[plan_id]

    if not held then
        return { kind = "trouble", text =
            "That plan is no longer available. Plans are held only until they "
         .. "run and are lost if neuron restarts -- a plan describes the world "
         .. "at one moment, and that moment has passed. Ask again." }
    end

    PLANS[id][plan_id] = nil

    local vocabulary = Conversations.vocabulary_of(handle, id) or "world"
    local registry = Registry.load(handle.neuron_root, vocabulary)
    local operation = registry and registry.by_name[held.operation]

    if not operation then
        return { kind = "trouble", text = string.format(
            "'%s' is not a word neuron knows any more.", tostring(held.operation)) }
    end

    local receipt = operation.apply(handle, held.plan, Liveness.probe(handle))
    local described = Receipts.describe(receipt)

    Transcript.append(handle, id, "you", "yes, do it")
    Transcript.append(handle, id, "result", described)

    return {
        kind    = receipt.outcome == "complete" and "done" or "trouble",
        text    = described,
        outcome = receipt.outcome,
    }
end
-- }}}

-- {{{ Conversations.plans(id)
function Conversations.plans(id)
    local waiting = {}
    for identifier in pairs(PLANS[id] or {}) do table.insert(waiting, identifier) end
    table.sort(waiting)
    return waiting
end
-- }}}

return Conversations
