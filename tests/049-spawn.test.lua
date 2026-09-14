--------------------------------------------------------------------------------
-- tests/049-spawn.test.lua
--
-- The parts of world.spawn that need no world: the scatter geometry and the
-- script it installs.
--
-- A plan needs the database (to resolve a place and confirm a creature exists),
-- so it is not exercised here. What is exercised is everything that decides
-- WHERE creatures end up and what the worldserver is actually asked to do --
-- which is where the bugs that survive to production live, because a wrong
-- position does not error, it just puts a monster in the sea.
--------------------------------------------------------------------------------

local NEURON = "/mnt/mtwo/games/azeroth-core/wow-chat-neuron"

local Load     = dofile(NEURON .. "/src/024-load.lua")
local Spawn    = Load(NEURON .. "/src/049-spawn.lua")
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

-- {{{ the declaration
local operation, why = Registry.define(Spawn.declaration, Spawn)
check("it registers",                    operation ~= nil,                   true)
if not operation then print(why) os.exit(1) end

check("it is a change, not final",       operation.kind.name,           "change")
check("resident is preferred",           operation.hands[1].name,     "resident")
check("cold is the fallback",            operation.hands[2].name,         "cold")
check("and there is no live form",       #operation.hands,                     2)
-- }}}

-- {{{ the installed script
-- What the worldserver is actually asked to do. A malformed script installs
-- perfectly and never runs, which looks exactly like the feature not working --
-- so the least it can do is parse.
local script = Spawn.script(1501, 1, -956.7, -3754.7, 5.3, 1.57, false)

check("the script is valid Lua",  loadstring(script) ~= nil,                true)
check("it spawns a creature (type 1)",
    script:find("PerformIngameSpawn(1, 1501", 1, true) ~= nil,              true)
check("on the right map",
    script:find("PerformIngameSpawn(1, 1501, 1,", 1, true) ~= nil,          true)

-- The ground is read from the map rather than taken from the place. A place's
-- recorded z is where a PLAYER teleports to, which for a dock or a bridge is not
-- the ground -- and a creature spawned at a player's z hangs in the air or
-- stands inside the terrain.
check("it asks the map for the ground",
    script:find("GetHeight", 1, true) ~= nil,                               true)
check("and probes from above the recorded z",
    script:find("15.3000", 1, true) ~= nil,                                 true)
check("spawning at the ground it found, not at the place's z",
    script:find("ground, 1.5700", 1, true) ~= nil,                          true)

-- No ground means open water or a hole in the terrain. Refusing loudly in the
-- server log beats dropping a creature into the sea, where the failure is
-- reported as the spawn silently not working.
check("it refuses when there is no ground",
    script:find("no ground at", 1, true) ~= nil,                            true)

local permanent = Spawn.script(1501, 1, 0, 0, 0, 0, true)
check("permanent is passed through",
    permanent:find(", true, 300)", 1, true) ~= nil,                         true)
check("and its absence too",
    script:find(", false, 300)", 1, true) ~= nil,                           true)
-- }}}

-- {{{ the scatter
-- A golden-angle spiral rather than a circle or a random scatter. A circle puts
-- everybody the same distance out, which reads as a summoning ritual; random
-- clumps and leaves gaps.
--
-- Reconstructed here from the same constants rather than called, because plan
-- needs a database. What is being checked is that the shape does what it claims.
local GOLDEN = math.pi * (3 - math.sqrt(5))

local function scatter(count, spread)
    local points = {}
    for index = 1, count do
        local bearing = index * GOLDEN
        local radius  = count == 1 and 0 or (spread * math.sqrt(index / count))
        table.insert(points, { x = math.cos(bearing) * radius,
                               y = math.sin(bearing) * radius,
                               r = radius })
    end
    return points
end

local one = scatter(1, 8)
check("a single creature stands on the spot",  one[1].r,                        0)

local twelve = scatter(12, 8)
check("twelve are spread",   #twelve,                                          12)
check("none further than the spread",  twelve[12].r <= 8.0001,               true)
check("and they fill outward",  twelve[1].r < twelve[12].r,                  true)

-- No two at the same bearing, which is what stops a line of them overlapping.
local same_bearing = false
for a = 1, #twelve do
    for b = a + 1, #twelve do
        local gap = math.abs((a * GOLDEN) % (2 * math.pi) - (b * GOLDEN) % (2 * math.pi))
        if gap < 0.01 or math.abs(gap - 2 * math.pi) < 0.01 then same_bearing = true end
    end
end
check("no two share a bearing",  same_bearing,                              false)

-- Even area per creature rather than a crowded middle: radius grows as the
-- square root of the index, so the gap between successive rings shrinks.
local first_gap = twelve[2].r - twelve[1].r
local last_gap  = twelve[12].r - twelve[11].r
check("rings get closer further out",  last_gap < first_gap,                 true)
-- }}}

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
