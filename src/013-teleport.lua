--------------------------------------------------------------------------------
-- 013-teleport.lua
--
-- Move a roster to a place. The first operation that changes the world, and the
-- right first one, because it is the simplest thing that still needs BOTH hands
-- and therefore proves the whole model.
--
-- THE HAND IS CHOSEN PER CHARACTER, NOT PER OPERATION, because the right answer
-- differs between two characters in the same roster:
--
--   offline -> cold : nothing holds their state, so the row IS their position
--   online  -> live : a row write is overwritten by the server's next save
--
-- Getting that backwards is the silent failure the liveness guard exists for,
-- and this operation is where it would first have happened. The write lands, the
-- row changes, the tool reports success, and the server quietly puts it back.
--
-- POSITION IS FOUR NUMBERS AND A MAP. Writing the three coordinates without the
-- map produces a character at the right numbers on the wrong continent, which
-- looks exactly like the teleport having done nothing. And `zone` is stored on
-- the row but deliberately NOT written -- the server recomputes it from the
-- position at login, and a stale zone beside a fresh position produces a
-- character who is in Ratchet and believes they are in Menethil.
--
-- See issues/203-character-teleport.md for the blueprint.
--------------------------------------------------------------------------------

local Teleport = {}

-- {{{ sibling(neuron_root, filename)
local function sibling(neuron_root, filename)
    return dofile(neuron_root .. "/src/" .. filename)
end
-- }}}

-- {{{ Teleport.declaration
-- What this operation is, for the registry, the command line, and -- in phase 8
-- -- the tool schema handed to a model. One declaration, three surfaces, so
-- adding an operation cannot add a command without adding a tool.
Teleport.declaration = {
    name    = "character.teleport",
    summary = "Move a roster of characters to a named place.",
    -- Live is preferred because the change is instant and visible to everyone
    -- standing there. Cold is the fallback that also works with the world down,
    -- and is the ONLY thing that works for an offline character either way.
    hands   = { "live", "cold" },
    reversible = true,
    params  = {
        { name = "roster", type = "roster", required = true,
          describes = "Who to move: a name, a comma-separated list of names, "
                   .. "or a query like 'bots hunters 18-20'." },
        { name = "place", type = "place", required = true,
          describes = "Where to move them: a named location such as 'ratchet'." },
    },
}
-- }}}

-- {{{ Teleport.plan(handle, args)
-- Compute what would happen. Reads freely; writes NOTHING.
--
-- Returns a plan: the destination, the resolution, and an ordered list of steps.
-- The step descriptions are the operation's real interface -- a person reads
-- them far more often than they read this file, and a model's proposal is shown
-- as them.
function Teleport.plan(handle, args)
    local Rosters   = sibling(handle.neuron_root, "012-rosters.lua")
    local PlaceBook = sibling(handle.neuron_root, "011-place-book.lua")
    local WorldRead = sibling(handle.neuron_root, "005-world-read.lua")

    local place, why = PlaceBook.resolve(handle, args.place)
    if not place then
        return nil, why
    end

    local resolution, roster_why = Rosters.resolve(handle, args.roster, args)
    if not resolution then
        return nil, roster_why
    end

    if #resolution.characters == 0 then
        return nil, "that roster resolves to nobody, so there is nothing to move"
    end

    local steps = {}

    for _, character in ipairs(resolution.characters) do
        local from = WorldRead.MAPS[character.map] or ("map " .. tostring(character.map))

        local describes = string.format("%s  %s %.0f,%.0f  ->  %s",
            character.name, from, character.x, character.y, place.name)

        -- The branch that is the whole point of the operation.
        --
        -- ONLINE  -> the live hand, because the worldserver holds this
        --            character in memory and would overwrite a row write.
        -- OFFLINE -> the cold hand, because there is no in-memory copy and the
        --            row is the only thing that holds their position. The live
        --            hand cannot help here at all: a game master teleport needs
        --            a character present in the world.
        local step
        if character.online then
            -- `tele name` takes the game's own location names, which is exactly
            -- what the place book resolved. A project-only place has no name the
            -- game knows, so it cannot go this way.
            if place.known_to_game then
                step = {
                    hand      = "live",
                    describes = describes .. "  (online, by command)",
                    command   = "tele name " .. character.name .. " " .. place.name,
                    subject   = character,
                }
            else
                step = {
                    hand      = "refuse",
                    describes = describes .. "  (online, and '" .. place.name
                             .. "' is a project place the game does not know)",
                    subject   = character,
                    reason    = "the game master teleport command only accepts "
                             .. "locations the game itself knows; this place is "
                             .. "ours, so this character must be offline to move "
                             .. "there",
                }
            end
        else
            step = {
                hand      = "cold",
                describes = describes,
                sql       = "UPDATE characters SET map = ?, position_x = ?, "
                         .. "position_y = ?, position_z = ?, orientation = ? "
                         .. "WHERE guid = ?",
                binds     = { place.map, place.x, place.y, place.z,
                              place.o or 0, character.guid },
                -- What this step puts there, by column name. Recorded in the
                -- receipt so a later undo can ask "has anything moved them since
                -- I did?" rather than the useless "are they somewhere other than
                -- where they started?", which is true by construction.
                wrote     = { map = place.map, position_x = place.x,
                              position_y = place.y, position_z = place.z,
                              orientation = place.o or 0 },
                subject   = character,
                -- Recorded so the guard knows a live alternative exists. A
                -- character who logs in between planning and applying is
                -- REROUTED here rather than written and hoped for.
                live_form = place.known_to_game
                            and ("tele name " .. character.name .. " " .. place.name)
                            or nil,
                -- What to read before overwriting, so the receipt can put them
                -- back. This is what makes the operation reversible.
                restores_from = {
                    table  = "characters",
                    key    = { guid = character.guid },
                    fields = { "map", "position_x", "position_y",
                               "position_z", "orientation" },
                },
            }
        end

        table.insert(steps, step)
    end

    return {
        operation  = Teleport.declaration.name,
        place      = place,
        resolution = resolution,
        steps      = steps,
    }
end
-- }}}

-- {{{ Teleport.describe_plan(plan)
-- The plan, rendered for a person to approve.
function Teleport.describe_plan(plan)
    local Rosters = nil  -- described inline; the resolution carries its own text
    local lines = {}

    table.insert(lines, string.format("move %d character%s to %s (%s  %.1f %.1f %.1f)",
        #plan.steps, #plan.steps == 1 and "" or "s",
        plan.place.name,
        plan.place.map_name or ("map " .. tostring(plan.place.map)),
        plan.place.x, plan.place.y, plan.place.z))

    if not plan.place.is_open_world then
        table.insert(lines, "")
        table.insert(lines, "WARNING: that place is not on an open-world map, so it is "
            .. "inside an instance.")
        table.insert(lines, "         Writing an offline character there may produce a "
            .. "character who")
        table.insert(lines, "         cannot log in, because the server expects an "
            .. "instance binding")
        table.insert(lines, "         that does not exist.")
    end

    table.insert(lines, "")

    for _, step in ipairs(plan.steps) do
        table.insert(lines, string.format("  %-7s %s", step.hand, step.describes))
    end

    if #plan.resolution.missing > 0 then
        table.insert(lines, "")
        table.insert(lines, "MISSING: no character named "
            .. table.concat(plan.resolution.missing, ", "))
    end

    if plan.resolution.truncated then
        table.insert(lines, "")
        table.insert(lines, string.format(
            "TRUNCATED at %d -- more characters match than that.",
            plan.resolution.ceiling))
    end

    return table.concat(lines, "\n")
end
-- }}}

-- {{{ read_prior(handle, spec)
-- Read the values a step is about to overwrite.
--
-- One query per write. That is the cost of reversibility and it is paid every
-- time, because a receipt without prior values is a receipt that cannot put
-- anybody back.
local function read_prior(handle, spec)
    local ColdHand = sibling(handle.neuron_root, "002-cold-hand.lua")

    local rows, why = ColdHand.read(handle, handle.db_characters,
        "SELECT " .. table.concat(spec.fields, ", ")
        .. " FROM " .. spec.table .. " WHERE guid = ?",
        { spec.key.guid })

    if not rows then
        return nil, why
    end
    if #rows == 0 then
        return nil, "the character to be changed no longer exists"
    end
    return rows[1]
end
-- }}}

-- {{{ Teleport.apply(handle, plan, state)
-- Execute the plan. Returns a receipt.
--
-- A step that FAILS STOPS THE RUN. Remaining steps are marked skipped. There is
-- no automatic rollback of what already succeeded: rolling back needs the same
-- guards and the same liveness as going forward, and a failed rollback inside a
-- failed apply is a worse place to be than a partial change with an exact record
-- of itself. Reversal is a deliberate second operation, driven by the receipt.
function Teleport.apply(handle, plan, state)
    local ColdHand = sibling(handle.neuron_root, "002-cold-hand.lua")
    local LiveHand = sibling(handle.neuron_root, "003-live-hand.lua")
    local Liveness = sibling(handle.neuron_root, "004-liveness.lua")
    local Receipts = sibling(handle.neuron_root, "006-receipts.lua")

    local receipt = Receipts.begin(handle, plan.operation, {
        roster = plan.resolution.describes,
        place  = plan.place.name,
    })

    local stopped = false

    for _, step in ipairs(plan.steps) do
        if stopped then
            Receipts.record(receipt, step, "skipped")

        elseif step.hand == "refuse" then
            Receipts.record(receipt, step, "refused", nil, step.reason)

        else
            -- The guard runs HERE, immediately before the write, not at plan
            -- time. The minutes between planning and approving are minutes in
            -- which somebody can log in.
            local verdict, guard_why = Liveness.guard_step(handle, state, step)

            if verdict == "refuse" then
                Receipts.record(receipt, step, "refused", nil, guard_why)
                stopped = true

            elseif verdict == "reroute" then
                -- They logged in since the plan was made. Use the live form.
                local output, live_why = LiveHand.execute(handle, step.live_form)
                if output then
                    Receipts.record(receipt, step, "rerouted", nil, output)
                else
                    Receipts.record(receipt, step, "failed", nil, live_why)
                    stopped = true
                end

            elseif step.hand == "live" then
                local output, live_why = LiveHand.execute(handle, step.command)
                if output then
                    Receipts.record(receipt, step, "done", nil, output)
                else
                    Receipts.record(receipt, step, "failed", nil, live_why)
                    stopped = true
                end

            else
                -- Cold. Capture what is about to be overwritten FIRST.
                local prior, prior_why = read_prior(handle, step.restores_from)
                if not prior then
                    Receipts.record(receipt, step, "failed", nil, prior_why)
                    stopped = true
                else
                    local affected, write_why = ColdHand.write(handle,
                        handle.db_characters, step.sql, step.binds)

                    if not affected then
                        Receipts.record(receipt, step, "failed", prior, write_why)
                        stopped = true
                    elseif affected == 0 then
                        -- Zero affected rows after a successful prior read means
                        -- the character was already exactly there. Not an error,
                        -- and worth saying so rather than reporting a change
                        -- that did not happen.
                        Receipts.record(receipt, step, "done", prior,
                            "already at that position; no row changed")
                    else
                        Receipts.record(receipt, step, "done", prior,
                            string.format("%d row changed", affected))
                    end
                end
            end
        end
    end

    Receipts.finish(receipt)

    local path, append_why = Receipts.append(handle, receipt)
    if not path then
        -- The world may already have changed. Losing the record of that is the
        -- one failure the receipt module exists to prevent, so it is reported
        -- loudly rather than swallowed.
        receipt.receipt_write_failed = append_why
    end

    return receipt
end
-- }}}

return Teleport
