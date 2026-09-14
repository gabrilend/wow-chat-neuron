--------------------------------------------------------------------------------
-- tests/banners.test.lua
--
-- Every source file says its own name on line 2, and says the right one.
--
-- This exists because seven files once said the wrong one. The enums were
-- written before the rule that a GROUP DIRECTORY takes an index of its own, so
-- when `src/025-enums/` claimed 025 every file inside it shifted up by one --
-- and the shift moved the filenames without moving the banner comments. For a
-- while `026-enum.lua` opened with `-- 025-enum.lua`.
--
-- Nothing catches that on its own. The banner is a comment, so it cannot fail
-- to compile, cannot fail a load, and cannot make a single behavioural test go
-- red. It is read by people and by greps, both of which will believe it -- and
-- a grep for `025-enum` finding the file that is no longer 025 is a grep that
-- has quietly answered the wrong question.
--
-- The index is the reading order of the whole project, so a file whose banner
-- disagrees with its name has two positions in the story at once.
--------------------------------------------------------------------------------

local NEURON = "/mnt/mtwo/games/azeroth-core/wow-chat-neuron"

local passed, failed = 0, 0

-- {{{ check(label, got, want)
local function check(label, got, want)
    if got == want then
        passed = passed + 1
    else
        failed = failed + 1
        print(string.format("FAIL  %s\n        got  %s\n        want %s",
            label, tostring(got), tostring(want)))
    end
end
-- }}}

-- {{{ banner_of(path)
-- The name a file claims for itself: line 2, with the comment marker taken off
-- and any trailing whitespace with it.
--
-- Line 2 and not "somewhere near the top", because the header shape is fixed --
-- a rule of dashes, then the name, then a blank comment line, then the summary.
-- Searching for the name anywhere in the header would find it in prose too, and
-- then pass on a file whose real banner is wrong.
local function banner_of(path)
    local file = io.open(path, "r")
    if not file then return nil end

    file:read("*l")                        -- the rule of dashes
    local line = file:read("*l")
    file:close()

    if not line then return nil end
    return (line:gsub("^%-%-%s*", ""):gsub("%s+$", ""))
end
-- }}}

-- {{{ every source file
local listing = io.popen("find '" .. NEURON .. "/src' -name '*.lua' | sort", "r")

if not listing then
    print("FAIL  cannot list the source directory")
    os.exit(1)
end

local seen = 0

for path in listing:lines() do
    local basename = path:gsub(".*/", "")
    local short    = path:gsub(".*/src/", "src/")

    check(short .. " names itself", banner_of(path), basename)
    seen = seen + 1
end

listing:close()

-- A find that matched nothing would pass every check above by running none of
-- them, which is the one way this test can be green and mean nothing.
check("the source tree was actually walked", seen > 40, true)
-- }}}

-- {{{ the index in the name is the index in the path
-- A file inside a group directory carries an index HIGHER than the directory's,
-- because the directory took one. Getting this backwards is the exact mistake
-- the banners recorded, so it is worth stating as its own property.
local grouped = io.popen(
    "find '" .. NEURON .. "/src' -mindepth 2 -name '*.lua' | sort", "r")

if grouped then
    local groups = 0

    for path in grouped:lines() do
        local directory = path:match("/src/(%d+)%-[^/]+/")
        local file      = path:match("/(%d+)%-[^/]+%.lua$")

        if directory and file then
            check(path:gsub(".*/src/", "src/") .. " sits above its group",
                tonumber(file) > tonumber(directory), true)
            groups = groups + 1
        end
    end

    grouped:close()
    check("the group directories were walked", groups > 10, true)
end
-- }}}

-- {{{ report
print(string.format("banners: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
-- }}}
