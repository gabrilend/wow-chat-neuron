--------------------------------------------------------------------------------
-- 062-asking-levers.lua
--
-- The levers for configuring where neuron sends its thinking. A separate,
-- much smaller vocabulary, for a separate conversation.
--
-- WHY THESE ARE NOT IN THE WORLD'S REGISTRY:
--
-- The model that adjusts the inference configuration must not be able to
-- teleport anybody, and the model that runs the world must not be able to point
-- neuron somewhere else mid-sentence. Two registries rather than one with a
-- filter, because a filter is a rule somebody can get wrong and two tables are
-- two tables.
--
-- WHAT THE ADMIN MODEL IS TOLD, AND WHAT IT IS NOT:
--
-- It is told it is configuring a connection to a remote inference service. That
-- is the honest description of the job -- these levers set an endpoint, a model
-- name, a timeout -- and it is the whole of what it needs.
--
-- It is NOT told which endpoint is currently answering it. It might be a
-- machine across the world; it might be the process next to it. That is
-- deliberate: a model that knows it is running locally starts reasoning about
-- its own limits, offers to do less, and treats the configuration as being
-- about itself. One that believes it is configuring a pipe for somebody else
-- configures the pipe.
--
-- Nothing here lies. It simply does not say, and the difference matters --
-- the levers describe a remote service because that is what they configure.
--------------------------------------------------------------------------------

local Levers = {}

-- {{{ sibling(neuron_root, filename)
local function sibling(neuron_root, filename)
    return dofile(neuron_root .. "/src/" .. filename)
end
-- }}}

-- {{{ CONFIG_PATH
local function config_path(handle)
    return handle.neuron_root .. "/config/asking.lua"
end
-- }}}

-- {{{ rewrite(handle, setting, value, quoted)
-- Change one value in config/asking.lua, in place, leaving everything else --
-- including every comment -- exactly as it was.
--
-- A line edit rather than reading the table and writing it back out. Writing it
-- back would discard every comment in the file, and that file is mostly
-- comments explaining why each number is what it is. A configuration that
-- forgets its own reasoning the first time it is adjusted is worse than one
-- that cannot be adjusted.
local function rewrite(handle, setting, value, quoted)
    local path = config_path(handle)

    local file = io.open(path, "r")
    if not file then
        return nil, "config/asking.lua is not there to edit."
    end

    local text = file:read("*a")
    file:close()

    local rendered = quoted and string.format("%q", tostring(value))
                             or tostring(value)

    -- Anchored to exactly four spaces of indentation, which is the top level
    -- of the returned table.
    --
    -- Not merely tidiness: `timeout_seconds` appears TWICE in that file -- once
    -- for the configured service and once inside the `bench` block, indented
    -- eight -- and the bench's comes first. A pattern matching any indentation
    -- edited the wrong one, silently, and the setting somebody asked to change
    -- stayed exactly as it was while a different one moved.
    local pattern = "(\n    " .. setting .. "%s*=%s*)([^,\n]*)(,)"
    local changed, count = text:gsub(pattern, function(before, was, after)
        return before .. rendered .. after
    end, 1)

    if count == 0 then
        return nil, string.format(
            "there is no top-level line setting '%s' in config/asking.lua.\n"
         .. "  This edits an existing line rather than adding one, so the comment\n"
         .. "  above it -- which says why the value is what it is -- stays\n"
         .. "  attached to it. It matches only the outermost level, so a setting\n"
         .. "  of the same name inside a nested block is never touched by\n"
         .. "  accident.", setting)
    end

    local out = io.open(path, "w")
    if not out then
        return nil, "config/asking.lua could not be written."
    end
    out:write(changed)
    out:close()

    return true
end
-- }}}

-- {{{ Levers.rewrite_bench(handle, setting, value)
-- Change one setting INSIDE the bench block.
--
-- A separate function rather than an argument to `rewrite`, because the two
-- anchor on different things and confusing them is the exact bug `rewrite`'s
-- four-space anchor exists to prevent: `timeout_seconds` and `model` both
-- appear at the top level and inside `bench`, and the bench copy comes first
-- in the file.
--
-- Anchored on eight spaces, and only within the text after `bench = {`. The
-- bench block is the only eight-space region in that file today; scoping to it
-- anyway means that stays true by construction rather than by luck.
function Levers.rewrite_bench(handle, setting, value, quoted)
    local path = config_path(handle)

    local file = io.open(path, "r")
    if not file then
        return nil, "config/asking.lua is not there to edit."
    end

    local text = file:read("*a")
    file:close()

    local at = text:find("\n    bench%s*=%s*{")
    if not at then
        return nil, "config/asking.lua has no bench block, so there is no "
                 .. "local model described in it to change."
    end

    local head, tail = text:sub(1, at - 1), text:sub(at)

    local rendered = quoted and string.format("%q", tostring(value))
                             or tostring(value)

    local pattern = "(\n        " .. setting .. "%s*=%s*)([^,\n]*)(,)"
    local changed, count = tail:gsub(pattern, function(before, was, after)
        return before .. rendered .. after
    end, 1)

    if count == 0 then
        return nil, string.format(
            "the bench block in config/asking.lua has no line setting '%s'.\n"
         .. "  This edits an existing line rather than adding one, so the\n"
         .. "  comment above it stays attached to it.", setting)
    end

    local out = io.open(path, "w")
    if not out then
        return nil, "config/asking.lua could not be written."
    end
    out:write(head .. changed)
    out:close()

    return true
end
-- }}}

-- {{{ Levers.Status
Levers.Status = {}

Levers.Status.declaration = {
    name    = "asking.status",
    summary = "Report the current configuration for reaching the inference "
           .. "service: which endpoint, which model, which timeouts, and "
           .. "whether a credential is present.",
    kind    = "read",
    hands   = { "none" },
    params  = {},
}

function Levers.Status.run(handle, args)
    local Keys   = sibling(handle.neuron_root, "052-keys.lua")
    local asking = handle.asking or {}

    local have_key = Keys.present(handle.api_key_path, "the credential")

    local bench = asking.bench or {}

    -- The local model first, because in this window it is the one answering.
    local lines = {
        "local model   " .. tostring(bench.model)
            .. "   at " .. tostring(bench.url),
        "",
        "the remote service this window configures:",
        "  endpoint    " .. tostring(asking.url),
        "  model       " .. tostring(asking.model),
        "  credential  " .. (have_key and "present" or "ABSENT"),
        "  timeout     " .. tostring(asking.timeout_seconds) .. "s",
    }

    return { describes = table.concat(lines, "\n") }
end
-- }}}

-- {{{ receipt_for(handle, operation, arguments, plan, ok, why)
-- One receipt, built the way every other lever builds one.
--
-- These three used to assemble a table by hand, and it was missing the three
-- fields that identify a receipt at all: its id, which deployment it belongs
-- to, and which profile was active. Receipts.describe prints those first, so
-- agreeing to a change answered with "nil  asking.timeout  [complete]" and
-- "1788679087 on nil (nil)" -- a receipt that cannot say what it is a receipt
-- OF. The timestamps were raw epoch seconds too, where every other receipt
-- carries a readable one.
--
-- Nothing here is a special case; it is the ordinary path, which is why it goes
-- through Receipts.begin / record / finish rather than reproducing their
-- output. A second way of building a receipt is a second thing to keep in step.
local function receipt_for(handle, operation, arguments, plan, ok, why)
    local Receipts = sibling(handle.neuron_root, "006-receipts.lua")

    local receipt = Receipts.begin(handle, operation, arguments)

    Receipts.record(receipt, {
        describes = plan.steps[1].describes,
        -- "none" as a STRING, which is what every other lever puts on a step
        -- and what Receipts.describe prints with %-4s. The hands enum is for
        -- routing a step to a mechanism; a receipt is a record, and what it
        -- records is the name.
        --
        -- The none hand is the right one here: this changes a file that
        -- belongs to neuron, so no database and no running server is touched.
        hand = "none",
    }, ok and "done" or "failed", nil,
       ok and ("was " .. tostring(plan.was)) or why)

    return Receipts.finish(receipt, ok and "complete" or "refused")
end
-- }}}

-- {{{ Levers.Endpoint
Levers.Endpoint = {}

Levers.Endpoint.declaration = {
    name    = "asking.endpoint",
    summary = "Set the address of the inference service neuron sends requests "
           .. "to. Changing this does not test it -- use asking.check for that.",
    kind    = "change",
    hands   = { "none" },
    params  = {
        { name = "url", type = "string", required = true,
          describes = "The full address requests are posted to, including the "
                   .. "scheme and path. For example "
                   .. "https://example.invalid/v1/messages." },
    },
}

function Levers.Endpoint.plan(handle, args)
    local url = tostring(args.url or "")

    if not url:match("^https?://") then
        return nil, string.format(
            "'%s' is not an address requests can be posted to.\n"
         .. "  It needs a scheme -- http:// or https:// -- and a host.", url)
    end

    return {
        operation = "asking.endpoint",
        was       = handle.asking and handle.asking.url,
        will_be   = url,
        steps     = { { describes = "point requests at " .. url } },
    }
end

function Levers.Endpoint.describe_plan(plan)
    return string.format(
        "change the inference endpoint\n\n  from  %s\n  to    %s\n\n"
     .. "Nothing is sent to verify it. Run asking.check afterwards.",
        tostring(plan.was), plan.will_be)
end

function Levers.Endpoint.apply(handle, plan, state)
    local ok, why = rewrite(handle, "url", plan.will_be, true)

    return receipt_for(handle, "asking.endpoint", { url = plan.will_be },
                       plan, ok, why)
end
-- }}}

-- {{{ Levers.Model
Levers.Model = {}

Levers.Model.declaration = {
    name    = "asking.model",
    summary = "Set which model the inference service is asked for. The name "
           .. "must be one that service recognises; neuron cannot check that "
           .. "without sending a request.",
    kind    = "change",
    hands   = { "none" },
    params  = {
        { name = "name", type = "string", required = true,
          describes = "The model identifier, exactly as the service names it." },
    },
}

function Levers.Model.plan(handle, args)
    local name = tostring(args.name or ""):gsub("^%s+", ""):gsub("%s+$", "")

    if name == "" then
        return nil, "asking.model needs a model name."
    end

    return {
        operation = "asking.model",
        was       = handle.asking and handle.asking.model,
        will_be   = name,
        steps     = { { describes = "ask for the model " .. name } },
    }
end

function Levers.Model.describe_plan(plan)
    return string.format(
        "change which model is asked for\n\n  from  %s\n  to    %s\n\n"
     .. "Whether the service has it is not knowable from here. Run asking.check.",
        tostring(plan.was), plan.will_be)
end

function Levers.Model.apply(handle, plan, state)
    local ok, why = rewrite(handle, "model", plan.will_be, true)

    return receipt_for(handle, "asking.model", { name = plan.will_be },
                       plan, ok, why)
end
-- }}}

-- {{{ Levers.Check
Levers.Check = {}

Levers.Check.declaration = {
    name    = "asking.check",
    summary = "Send one trivial request to the configured inference service and "
           .. "report exactly what came back -- whether it answered, how long "
           .. "it took, and the wording of any refusal.",
    kind    = "read",
    hands   = { "none" },
    params  = {},
}

function Levers.Check.run(handle, args)
    local Api = sibling(handle.neuron_root, "050-api.lua")

    -- Wall clock, via curl's own measurement further down. os.clock() is CPU
    -- time consumed by THIS process -- which spends the whole request asleep
    -- waiting for a socket, so it reported 0.0 seconds for a request that took
    -- three.
    local began = os.time()

    -- Deliberately tiny. This asks whether the pipe carries anything, not
    -- whether the thing at the other end is clever.
    local reply, kind, why = Api.send(handle, {
        system   = "Answer with one word.",
        messages = { { role = "user", content = "Say: ready" } },
        tools    = {},
    })

    local took = os.time() - began

    if not reply then
        return { describes = string.format(
            "The service did not answer.\n\nkind      %s\n\n%s",
            tostring(kind), tostring(why)) }
    end

    local said = ""
    for _, block in ipairs(reply.content or {}) do
        if block.type == "text" then said = said .. (block.text or "") end
    end

    -- `stop_reason` is why the model stopped talking: end_turn means it
    -- finished, tool_use means it wanted to call something, max_tokens means it
    -- was cut off. Worth showing, because "it answered and stopped at
    -- max_tokens" is a working connection and a too-small limit.
    return { describes = string.format(
        "The service answered in about %d second%s.\n\n"
     .. "  it said       %s\n"
     .. "  why it stopped  %s",
        took, took == 1 and "" or "s",
        said:gsub("%s+", " "), tostring(reply.stop_reason)) }
end
-- }}}

-- {{{ Levers.Timeout
Levers.Timeout = {}

Levers.Timeout.declaration = {
    name    = "asking.timeout",
    summary = "Set how many seconds one request may take before it is "
           .. "abandoned. A whole answer, not a first token.",
    kind    = "change",
    hands   = { "none" },
    params  = {
        { name = "seconds", type = "integer", required = true,
          describes = "How long to wait. Long enough for a full answer with "
                   .. "many tool calls in it; short enough that a hung request "
                   .. "does not hold a window open until somebody notices." },
    },
}

function Levers.Timeout.plan(handle, args)
    local seconds = math.floor(tonumber(args.seconds) or 0)

    if seconds < 5 or seconds > 3600 then
        return nil, string.format(
            "%d seconds is outside what this can be set to (5 to 3600).\n"
         .. "  Below five, a request that was going to succeed is cut off; above\n"
         .. "  an hour, a hung one is indistinguishable from a slow one.", seconds)
    end

    return {
        operation = "asking.timeout",
        was       = handle.asking and handle.asking.timeout_seconds,
        will_be   = seconds,
        steps     = { { describes = "wait up to " .. seconds .. " seconds" } },
    }
end

function Levers.Timeout.describe_plan(plan)
    return string.format("change the request timeout\n\n  from  %s seconds\n"
        .. "  to    %d seconds", tostring(plan.was), plan.will_be)
end

function Levers.Timeout.apply(handle, plan, state)
    local ok, why = rewrite(handle, "timeout_seconds", plan.will_be, false)

    return receipt_for(handle, "asking.timeout", { seconds = plan.will_be },
                       plan, ok, why)
end
-- }}}

return Levers
