--------------------------------------------------------------------------------
-- 049-spawn.lua
--
-- `world.spawn` -- put creatures in the world.
--
-- The first word that CREATES something. Everything before it moved, dressed or
-- removed things that already existed, which meant the whole asking half of the
-- project could have been finished and "make me some undead" would still have
-- been unanswerable.
--
-- WHY THIS IS A RESIDENT OPERATION, which is the whole design of the file:
--
--   live     .npc add spawns at the CALLER'S position. A SOAP caller has no
--            body in the world and cannot get one, so the command has nowhere
--            to put anything. Same limit 003-live-hand.lua already records for
--            gobject add.
--
--   cold     An INSERT into `creature` is durable and correct, and the
--            worldserver loads spawns WHEN A GRID LOADS. A grid with somebody
--            standing in it is already loaded and will not reload -- so the
--            creature exists in the database and not in the world, possibly
--            forever. The write succeeded, the tool reported success, and
--            nothing appeared.
--
--   resident ALE's PerformIngameSpawn runs INSIDE the worldserver and produces
--            a creature immediately, visible to everyone standing there. The
--            deployment's own ambush system already uses this call, which makes
--            it proven rather than proposed.
--
-- So hands are { resident, cold }: resident because it works now, cold as the
-- form that survives the world being down and is honest in its plan line about
-- appearing later.
--
-- NUMBERING: this sits at 049 rather than beside the other operations at
-- 011-016, because the project's index counts up across the whole tree and
-- those numbers were taken. Reading order and writing order have come apart
-- here; docs/reading-order.md is the index that still puts it with its kin.
--------------------------------------------------------------------------------

local Spawn = {}

-- {{{ sibling(neuron_root, filename)
local function sibling(neuron_root, filename)
    return dofile(neuron_root .. "/src/" .. filename)
end
-- }}}

-- {{{ Spawn.declaration
Spawn.declaration = {
    name    = "world.spawn",
    summary = "Place creatures of a chosen kind at or near a named place.",
    kind    = "change",
    hands   = { "resident", "cold" },
    params  = {
        { name = "creature", type = "integer", required = true,
          describes = "The creature kind's entry number, as returned by "
                   .. "world.creatures. Not a name -- names are not unique and "
                   .. "several hundred things are called 'Skeleton'." },
        { name = "place", type = "place", required = true,
          describes = "Where to put them: a named location such as 'ratchet'." },
        { name = "count", type = "integer", required = false, default = 1,
          describes = "How many. They are spread around the place rather than "
                   .. "stacked on it." },
        { name = "spread", type = "integer", required = false, default = 8,
          describes = "How many yards apart to scatter them. Small numbers make "
                   .. "one group; large ones make a line somebody walks along." },
        { name = "permanent", type = "boolean", required = false, default = false,
          describes = "Whether they survive a server restart. Left alone, they "
                   .. "vanish when the worldserver next stops, which is what "
                   .. "you want for an encounter and not for a settlement." },
    },
}
-- }}}

-- {{{ SCATTER
-- Where the members of a group stand relative to the place.
--
-- A golden-angle spiral rather than a circle or a random scatter. A circle puts
-- everybody the same distance out, which reads as a summoning ritual; random
-- clumps and leaves gaps. The golden angle fills outward evenly with no two at
-- the same bearing, which looks like a group of things that happen to be
-- standing there.
local GOLDEN_ANGLE = math.pi * (3 - math.sqrt(5))   -- 2.39996 radians
-- }}}

-- {{{ Spawn.plan(handle, args)
-- Compute what would happen. Reads freely; writes NOTHING.
function Spawn.plan(handle, args)
    local PlaceBook = sibling(handle.neuron_root, "011-place-book.lua")

    local place, why = PlaceBook.resolve(handle, args.place)
    if not place then
        return nil, why
    end

    local entry = math.floor(tonumber(args.creature) or 0)
    if entry <= 0 then
        return nil, string.format(
            "world.spawn needs a creature entry number, got '%s'.\n"
         .. "  Entry numbers come from world.creatures. A name will not do --\n"
         .. "  several hundred rows are called 'Skeleton' and they are different\n"
         .. "  creatures at different levels.", tostring(args.creature))
    end

    -- Confirm the kind exists and remember what it is, so every step
    -- description can say a name rather than a number. A plan reading
    -- "spawn 1501 at Ratchet" twenty times tells a reader nothing.
    --
    -- Read directly rather than through the bestiary, which filters for things
    -- worth fighting. A caller who has an entry number has already chosen, and
    -- refusing to look it up because it is a critter would be this word
    -- second-guessing a decision that was made upstream.
    local cold = sibling(handle.neuron_root, "002-cold-hand.lua")
    local rows, kind_why = cold.read(handle, handle.db_world,
        "SELECT entry, name, minlevel, maxlevel FROM creature_template WHERE entry = ?",
        { entry })

    if not rows then
        return nil, "world.spawn could not read the bestiary: " .. tostring(kind_why)
    end

    if #rows == 0 then
        return nil, string.format(
            "there is no creature kind numbered %d.\n"
         .. "  Entry numbers come from world.creatures, which only returns kinds\n"
         .. "  that have a model and a level band. A number from somewhere else\n"
         .. "  may be a quest trigger, or may not exist at all.", entry)
    end

    local kind = rows[1]

    local count  = math.floor(tonumber(args.count)  or 1)
    local spread = tonumber(args.spread) or 8

    if count < 1 then count = 1 end
    if count > 40 then
        return nil, string.format(
            "world.spawn was asked for %d of them, and stops at 40.\n"
         .. "  Forty creatures in one place is already a crowd nobody can fight.\n"
         .. "  A larger encounter is several spawns at several places, which is\n"
         .. "  also how it becomes something somebody walks through rather than\n"
         .. "  something that surrounds them.", count)
    end

    local steps = {}

    for index = 1, count do
        -- Golden-angle spiral: bearing turns by a constant irrational fraction
        -- of a circle, radius grows as the square root of the index so that
        -- area per creature stays even rather than crowding the middle.
        local bearing = index * GOLDEN_ANGLE
        local radius  = count == 1 and 0 or (spread * math.sqrt(index / count))

        local x = place.x + math.cos(bearing) * radius
        local y = place.y + math.sin(bearing) * radius

        table.insert(steps, {
            hand      = "resident",
            describes = string.format("%s (level %d-%d) at %s%s",
                kind.name, tonumber(kind.minlevel), tonumber(kind.maxlevel),
                place.name,
                radius > 0 and string.format(", %.0f yards out", radius) or ""),
            script_name = string.format("neuron_spawn_%d_%d",
                entry, math.floor(os.time())),
            script    = Spawn.script(entry, place.map, x, y, place.z, bearing,
                                     args.permanent and true or false),
            subject   = { entry = entry, name = kind.name },
            -- The cold form of the same step, for when the world is down. Its
            -- description says plainly that nothing appears yet, because a step
            -- whose description hides that is a step that lies.
            cold      = {
                sql = "INSERT INTO creature (id1, map, position_x, position_y, "
                   .. "position_z, orientation, spawntimesecs, spawndist, "
                   .. "MovementType) VALUES (?, ?, ?, ?, ?, ?, 300, 5, 1)",
                binds = { entry, place.map, x, y, place.z, bearing },
                database = handle.db_world,
                describes = string.format(
                    "%s at %s -- written to the database; appears when the area "
                 .. "next loads, which may be after a restart",
                    kind.name, place.name),
            },
        })
    end

    return {
        operation = Spawn.declaration.name,
        creature  = { entry = entry, name = kind.name,
                      minlevel = tonumber(kind.minlevel),
                      maxlevel = tonumber(kind.maxlevel) },
        place     = place,
        count     = count,
        spread    = spread,
        permanent = args.permanent and true or false,
        steps     = steps,
    }
end
-- }}}

-- {{{ Spawn.script(entry, map, x, y, z, orientation, permanent)
-- The Lua installed into the running worldserver.
--
-- It runs once when ALE loads it and does nothing afterwards, which is unusual
-- for a resident script -- most stay and keep deciding. This one is resident
-- only because that is the only hand that can reach PerformIngameSpawn, not
-- because it wants to live there.
--
-- The ground height is read from the map rather than taken from the place book.
-- A place's recorded z is where a PLAYER teleports to, which for a dock or a
-- bridge is not the ground, and a creature spawned at a player's z either hangs
-- in the air or stands inside the terrain.
function Spawn.script(entry, map, x, y, z, orientation, permanent)
    return string.format([[
-- neuron: one spawn, installed by world.spawn. Runs once and does nothing more.
local map = GetMapById(%d)

local ground = map and map:GetHeight(%.4f, %.4f, %.4f) or nil

-- A height of nil, or one absurdly far from where the place said, means there
-- is no ground there -- open water, or a hole in the terrain. Better to refuse
-- loudly in the server log than to drop a creature into the sea, where it will
-- be reported as the spawn silently not working.
if not ground or math.abs(ground - (%.4f)) > 40 then
    print("[neuron] world.spawn refused: no ground at %.1f,%.1f on map %d")
    return
end

PerformIngameSpawn(1, %d, %d, 0, %.4f, %.4f, ground, %.4f, %s, 300)
print("[neuron] world.spawn placed %d at %.1f,%.1f")
]],
        map,
        x, y, z + 10,       -- probe from above, so the ray finds the floor
        z,
        x, y, map,
        entry, map, x, y, orientation,
        permanent and "true" or "false",
        entry, x, y)
end
-- }}}

-- {{{ Spawn.describe_plan(plan)
-- What a person reads before agreeing to twenty of anything.
function Spawn.describe_plan(plan)
    local lines = {
        string.format("plan: place %d x %s (level %d-%d) at %s",
            plan.count, plan.creature.name,
            plan.creature.minlevel, plan.creature.maxlevel, plan.place.name),
        "",
    }

    for _, step in ipairs(plan.steps) do
        table.insert(lines, "  " .. step.describes)
    end

    table.insert(lines, "")

    if not plan.permanent then
        table.insert(lines,
            "These vanish when the worldserver next stops. Pass permanent to "
         .. "keep them.")
    else
        table.insert(lines,
            "PERMANENT: these are written to the database and survive a "
         .. "restart. Removing them is a separate act.")
    end

    return table.concat(lines, "\n")
end
-- }}}

-- {{{ Spawn.apply(handle, plan, state)
-- Walk the steps through whichever hand is up.
function Spawn.apply(handle, plan, state)
    local Mechanism = sibling(handle.neuron_root,
        "033-mechanisms/034-mechanism.lua")
    local Receipts  = sibling(handle.neuron_root, "006-receipts.lua")
    local Liveness  = sibling(handle.neuron_root, "004-liveness.lua")

    local mechanisms = Mechanism.dispatch(handle.neuron_root)
    local Hands      = Mechanism.Hands

    local hand, hand_why = Liveness.choose_hand(state, { "resident", "cold" })
    if not hand then
        return {
            operation = Spawn.declaration.name,
            outcome   = "refused",
            why       = hand_why,
            steps     = {},
        }
    end

    local member = Hands.of(hand)
    local record, started = {}, os.time()

    for index, step in ipairs(plan.steps) do
        -- The cold form is a different shape of step, carried on the same step
        -- so that choosing a hand does not mean rebuilding the plan.
        local carried = step
        if member == Hands.cold then
            carried = step.cold
        end

        local outcome = mechanisms[member].perform(handle, carried)

        table.insert(record, {
            describes = carried.describes,
            hand      = member.name,
            outcome   = outcome.ok and "done" or "failed",
            detail    = outcome.ok and outcome.detail or outcome.why,
        })

        -- A failing step stops the run. The receipt records what succeeded,
        -- what failed, and what was never attempted -- there is no automatic
        -- rollback, because a failed rollback inside a failed apply is a worse
        -- place to be than a partial change with an exact record of itself.
        if not outcome.ok then
            for later = index + 1, #plan.steps do
                table.insert(record, {
                    describes = plan.steps[later].describes,
                    hand      = member.name,
                    outcome   = "skipped",
                })
            end
            break
        end
    end

    local failures = 0
    for _, entry in ipairs(record) do
        if entry.outcome ~= "done" then failures = failures + 1 end
    end

    local receipt = {
        operation = Spawn.declaration.name,
        arguments = { creature = plan.creature.entry, place = plan.place.name,
                      count = plan.count, permanent = plan.permanent },
        started   = started,
        finished  = os.time(),
        steps     = record,
        outcome   = failures == 0 and "complete"
                 or (failures == #record and "refused" or "partial"),
    }

    Receipts.write(handle, receipt)
    return receipt
end
-- }}}

return Spawn
