--------------------------------------------------------------------------------
-- 061-broadcast.lua
--
-- `world.announce` -- say something to everybody logged in.
--
-- THIS IS A TEST LEVER AND IS MEANT TO BE DELETED. It exists to prove one
-- thing end to end: that a sentence can reach a lever, the lever can reach the
-- running world, and somebody standing in the game sees the result. Every other
-- operation either needs a character to act on, takes thirty seconds to
-- observe, or cannot be undone -- which makes all of them poor first tests.
--
-- This one changes nothing, is visible instantly, and costs nothing to get
-- wrong. When the pipeline has been proven once, delete the file, remove it
-- from the registry's list, and the vocabulary is smaller again.
--
-- It is declared `change` rather than `read` despite writing no row, because
-- everybody in the world sees it. A word that puts text on a stranger's screen
-- is not a read, whatever it does to the database.
--------------------------------------------------------------------------------

local Broadcast = {}

-- {{{ sibling(neuron_root, filename)
local function sibling(neuron_root, filename)
    return dofile(neuron_root .. "/src/" .. filename)
end
-- }}}

-- {{{ Broadcast.declaration
Broadcast.declaration = {
    name    = "world.announce",
    summary = "Say something to everybody currently logged in. Appears as a "
           .. "server message in their chat. TEMPORARY -- this exists to prove "
           .. "the pipeline works end to end and will be removed.",
    kind    = "change",
    -- Live only. There is no cold form: a message to people who are logged in
    -- has no meaning written to a database, and no meaning at all when nobody
    -- is there to read it.
    hands   = { "live" },
    params  = {
        { name = "message", type = "string", required = true,
          describes = "What to say. It appears to every player at once, "
                   .. "prefixed by the server, so keep it short and say who it "
                   .. "is from if that matters." },
    },
}
-- }}}

-- {{{ Broadcast.plan(handle, args)
function Broadcast.plan(handle, args)
    local message = tostring(args.message or ""):gsub("^%s+", ""):gsub("%s+$", "")

    if message == "" then
        return nil, "world.announce needs something to say."
    end

    -- Newlines would end the GM command early and leave the rest as garbage on
    -- the console. Refused rather than flattened, because a message silently
    -- losing its second half is worse than one that did not send.
    if message:find("[\n\r]") then
        return nil, "world.announce cannot send a message with line breaks in "
                 .. "it -- the console reads one line, and the rest would be "
                 .. "lost rather than shown."
    end

    local WorldRead = sibling(handle.neuron_root, "005-world-read.lua")

    -- Who will actually see it. A plan saying "tell everybody" when everybody
    -- is nobody is a plan that reads as working and does nothing.
    local online = {}
    local ok, found = pcall(WorldRead.characters_online, handle)
    if ok and found then online = found end

    return {
        operation = Broadcast.declaration.name,
        message   = message,
        audience  = online,
        steps = { {
            hand      = "live",
            command   = "announce " .. message,
            describes = string.format("say to everyone: %s", message),
        } },
    }
end
-- }}}

-- {{{ Broadcast.describe_plan(plan)
function Broadcast.describe_plan(plan)
    local who = #plan.audience

    local names = {}
    for _, character in ipairs(plan.audience) do
        table.insert(names, character.name)
    end

    return string.format("say to everybody logged in:\n\n  %s\n\n%s",
        plan.message,
        who == 0
            and "Nobody is logged in, so nobody will see it. The command still "
             .. "runs and the world still accepts it."
            or string.format("%d will see it: %s", who,
                table.concat(names, ", ")))
end
-- }}}

-- {{{ Broadcast.apply(handle, plan, state)
function Broadcast.apply(handle, plan, state)
    local Mechanism = sibling(handle.neuron_root,
        "033-mechanisms/034-mechanism.lua")
    local Receipts  = sibling(handle.neuron_root, "006-receipts.lua")

    local mechanisms = Mechanism.dispatch(handle.neuron_root)
    local Hands      = Mechanism.Hands

    local started = os.time()
    local outcome = mechanisms[Hands.live].perform(handle, plan.steps[1])

    local receipt = {
        operation = Broadcast.declaration.name,
        arguments = { message = plan.message },
        started   = started,
        finished  = os.time(),
        steps = { {
            describes = plan.steps[1].describes,
            hand      = "live",
            outcome   = outcome.ok and "done" or "failed",
            detail    = outcome.ok and outcome.detail or outcome.why,
        } },
        outcome = outcome.ok and "complete" or "refused",
    }

    Receipts.write(handle, receipt)
    return receipt
end
-- }}}

return Broadcast
