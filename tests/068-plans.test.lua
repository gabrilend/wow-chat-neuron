--------------------------------------------------------------------------------
-- 068-plans.test.lua
--
-- A plan made in one request must be findable in the next.
--
-- WHY THIS TEST EXISTS: `sibling()` loads with dofile, which RE-EXECUTES the
-- file. The menu loads the conversations module inside the request that handles
-- a route, so the copy that computed a plan and held it was thrown away when
-- that request finished, and the next request built a fresh module with an
-- empty table. Agreeing to a plan answered "that plan is no longer available"
-- every single time -- a true sentence about the wrong thing. The plan had not
-- expired; it had never been anywhere the second request could see.
--
-- The store lives in package.loaded, which the Lua runtime keeps one of per
-- process whatever route reaches it -- the same mechanism 024-load.lua uses.
--------------------------------------------------------------------------------

local ROOT = "/mnt/mtwo/games/azeroth-core/wow-chat-neuron"

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

-- {{{ two copies of the module, as two requests would have
local First  = dofile(ROOT .. "/src/068-conversations.lua")
local Second = dofile(ROOT .. "/src/068-conversations.lua")

check("dofile really does build two modules",
    rawequal(First, Second),                                              false)
-- }}}

-- {{{ the store is nevertheless one store
-- Reached through package.loaded, which is per process rather than per load.
local store = package.loaded["neuron.plans"]

check("there is a plan store",              type(store),                "table")
check("with a plans table in it",           type(store.plans),          "table")
check("and a counter beside them",          type(store.sequence),      "number")
-- }}}

-- {{{ what one copy puts there, the other finds
-- Written through the store directly, because putting a real plan in needs a
-- deployment and a database, and what is being tested is the STORE rather than
-- any particular plan.
store.plans["a-conversation"] = { ["plan-77"] = { operation = "asking.timeout" } }

local again = package.loaded["neuron.plans"]

check("the second copy sees the first copy's plan",
    again.plans["a-conversation"]["plan-77"].operation,        "asking.timeout")

check("and a third load does too",
    (function()
        dofile(ROOT .. "/src/068-conversations.lua")
        return package.loaded["neuron.plans"].plans["a-conversation"]["plan-77"]
            .operation
    end)(),                                                    "asking.timeout")
-- }}}

-- {{{ loading again does not empty it
-- The guard is `if not package.loaded[KEY]`, so a reload must leave what is
-- there alone. Reassigning on every load would put the bug straight back.
check("the counter survives a reload",
    (function()
        package.loaded["neuron.plans"].sequence = 41
        dofile(ROOT .. "/src/068-conversations.lua")
        return package.loaded["neuron.plans"].sequence
    end)(),                                                                  41)
-- }}}

store.plans["a-conversation"] = nil

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
