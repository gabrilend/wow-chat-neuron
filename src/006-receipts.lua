--------------------------------------------------------------------------------
-- 006-receipts.lua
--
-- The append-only record of what was done. Every apply produces one.
--
-- A receipt is not a log line for somebody skimming a terminal. It is the INPUT
-- to three other features, and its shape is set by what they need:
--
--   Reversal          needs the prior value of everything overwritten.
--   Renewal history   needs what a character was before it was renewed.
--   Narration         needs what happened, in terms a voice can describe.
--
-- The prior-value capture is the reason for all of it. Before any step that
-- overwrites a value, the previous value is read and stored. That read costs one
-- query per write and buys the entire reversal feature: forty characters can be
-- put back because the receipt knows where all forty were standing.
--
-- APPEND-ONLY IS NOT STYLISTIC. A receipt log that can be edited is a log that
-- cannot be trusted to say where those forty were, and that record is the only
-- reason an undo can run without a human checking each line first.
--
-- See issues/106-receipts.md for the blueprint.
--------------------------------------------------------------------------------

local Receipts = {}

-- {{{ sibling(neuron_root, filename)
local function sibling(neuron_root, filename)
    return dofile(neuron_root .. "/src/" .. filename)
end
-- }}}

-- {{{ timestamp()
-- ISO 8601 local time, seconds resolution.
--
-- Local rather than UTC because a person reading their own receipt log wants to
-- recognise when they did something. The offset is included so the value is
-- still unambiguous when it is read somewhere else.
local function timestamp()
    return os.date("%Y-%m-%dT%H:%M:%S%z")
end
-- }}}

-- {{{ receipt_id()
-- Time-prefixed and unique, so a directory listing sorts chronologically and two
-- receipts made in the same second do not collide.
--
-- The random suffix uses the clock as its seed source only once per process; a
-- per-call seed from os.time() would produce the SAME suffix for every receipt
-- made within one second, which is exactly the case it exists to handle.
local seeded = false
local function receipt_id()
    if not seeded then
        math.randomseed(os.time() + math.floor(os.clock() * 1000000))
        seeded = true
    end
    return os.date("%Y%m%dT%H%M%S") .. "-" .. string.format("%06x", math.random(0, 0xFFFFFF))
end
-- }}}

-- {{{ Receipts.begin(handle, operation, arguments)
-- Start a receipt. Returns a table that `apply` fills in as it goes.
--
-- Populated PROGRESSIVELY rather than assembled at the end. A run that dies
-- partway must still leave a record of the steps that finished, and a receipt
-- built only on success is a receipt that is missing exactly when it matters.
function Receipts.begin(handle, operation, arguments)
    return {
        id         = receipt_id(),
        operation  = operation,
        arguments  = arguments or {},
        deployment = handle.root,
        -- The profile is recorded because a receipt from the wrong profile must
        -- be unmistakable. Putting characters back where a DIFFERENT world's
        -- receipt says they were is a worse outcome than not putting them back.
        profile    = handle.profile,
        started    = timestamp(),
        finished   = nil,
        outcome    = "in-progress",
        steps      = {},
    }
end
-- }}}

-- {{{ Receipts.record(receipt, step, outcome, restores, evidence)
-- Add one step's result.
--
-- `restores` is a table of column names to the values that were there BEFORE
-- this step ran. It is the whole point. A step that overwrote nothing passes
-- nil; a step that overwrote a position passes every coordinate it replaced.
--
-- `step.wrote` -- the values the step PUT THERE -- is recorded alongside it, and
-- the pair is what makes drift detectable later. Knowing only the prior value,
-- an undo cannot tell "nobody has touched them since" from "they have moved
-- twice", because in both cases the current position differs from the prior one:
-- differing from the prior position is what a successful change MEANS. Comparing
-- against what was written is the question actually worth asking.
function Receipts.record(receipt, step, outcome, restores, evidence)
    table.insert(receipt.steps, {
        describes = step.describes,
        hand      = step.hand,
        outcome   = outcome,
        subject   = step.subject and {
            guid = step.subject.guid,
            name = step.subject.name,
        } or nil,
        restores  = restores,
        wrote     = step.wrote,
        evidence  = evidence,
    })
end
-- }}}

-- {{{ Receipts.finish(receipt, outcome)
-- Close a receipt.
--
-- Outcome is derived from the steps rather than asserted, so it cannot disagree
-- with them:
--
--   refused   nothing ran at all
--   complete  every step that ran succeeded
--   partial   some succeeded and something did not
--
-- "partial" is the one that matters. A run stops at the first failing step, so a
-- partial receipt describes a world that is half-changed, and the person reading
-- it needs to see that word without hunting for it.
function Receipts.finish(receipt, outcome)
    receipt.finished = timestamp()

    if outcome then
        receipt.outcome = outcome
        return receipt
    end

    local done, failed, skipped = 0, 0, 0
    for _, step in ipairs(receipt.steps) do
        if step.outcome == "done" or step.outcome == "rerouted" then
            done = done + 1
        elseif step.outcome == "failed" or step.outcome == "refused" then
            failed = failed + 1
        else
            skipped = skipped + 1
        end
    end

    if done == 0 then
        receipt.outcome = "refused"
    elseif failed == 0 and skipped == 0 then
        receipt.outcome = "complete"
    else
        receipt.outcome = "partial"
    end

    return receipt
end
-- }}}

-- {{{ ensure_directory(path)
-- Make the receipts directory if it is not there.
--
-- It lives under the shared-memory tier, which is RAM and does not survive a
-- reboot. So "not there" is a NORMAL state after every restart, not an error,
-- and anything writing a receipt must be prepared to create it.
local function ensure_directory(path)
    -- mkdir -p is idempotent and does not complain about an existing directory,
    -- which is the behaviour wanted here: the common case is that it exists.
    os.execute("mkdir -p '" .. path:gsub("'", "'\\''") .. "'")
end
-- }}}

-- {{{ Receipts.append(handle, receipt)
-- Write one receipt to today's log. One JSON object per line.
--
-- Opened in append mode, written, and FLUSHED immediately. Flushing per line is
-- the point: an unflushed receipt for a step that has already changed the world
-- is worse than no receipt, because the world moved and the record did not.
function Receipts.append(handle, receipt)
    local Json = sibling(handle.neuron_root, "001-json.lua")

    ensure_directory(handle.receipts_dir)

    local path = handle.receipts_dir .. "/" .. os.date("%Y-%m-%d") .. ".log"
    local file, why = io.open(path, "a")
    if not file then
        -- A receipt that cannot be written is not a warning. The operation may
        -- already have changed the world, and losing the record of that is the
        -- one failure this module exists to prevent.
        return nil, "cannot write a receipt to " .. path .. ": " .. tostring(why)
    end

    file:write(Json.encode(receipt), "\n")
    file:flush()
    file:close()

    return path
end
-- }}}

-- {{{ Receipts.read(handle, filter)
-- Read receipts back. `filter` may carry `operation`, `date`, or `guid`.
--
-- A line that will not parse is SKIPPED and counted rather than aborting the
-- read. The log is append-only and a truncated final line is what a process
-- killed mid-write leaves behind; refusing to read the other nine hundred good
-- receipts because of it would be the wrong trade.
function Receipts.read(handle, filter)
    filter = filter or {}
    local Json = sibling(handle.neuron_root, "001-json.lua")

    local date = filter.date or os.date("%Y-%m-%d")
    local path = handle.receipts_dir .. "/" .. date .. ".log"

    local file = io.open(path, "r")
    if not file then
        return {}, 0
    end

    local receipts, unreadable = {}, 0

    for line in file:lines() do
        if line:match("%S") then
            local receipt = Json.decode(line)
            if not receipt then
                unreadable = unreadable + 1
            else
                local keep = true

                if filter.operation and receipt.operation ~= filter.operation then
                    keep = false
                end

                if keep and filter.guid then
                    local touched = false
                    for _, step in ipairs(receipt.steps or {}) do
                        if step.subject and step.subject.guid == filter.guid then
                            touched = true
                            break
                        end
                    end
                    keep = touched
                end

                if keep then
                    table.insert(receipts, receipt)
                end
            end
        end
    end

    file:close()
    return receipts, unreadable
end
-- }}}

-- {{{ Receipts.describe(receipt)
-- One receipt, rendered for a person.
function Receipts.describe(receipt)
    local lines = {}
    table.insert(lines, string.format("%s  %s  [%s]",
        receipt.id, receipt.operation, receipt.outcome))
    table.insert(lines, string.format("  %s on %s (%s)",
        receipt.started, receipt.deployment, receipt.profile))

    for _, step in ipairs(receipt.steps or {}) do
        local mark = ({
            done     = "  ok  ",
            failed   = " FAIL ",
            refused  = " REFU ",
            skipped  = " skip ",
            rerouted = " redir",
        })[step.outcome] or "  ?   "
        table.insert(lines, string.format("  %s %-4s %s", mark, step.hand, step.describes))
    end

    return table.concat(lines, "\n")
end
-- }}}

return Receipts
