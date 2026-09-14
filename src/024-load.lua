--------------------------------------------------------------------------------
-- 024-load.lua
--
-- Load a source file once and hand back the same value every time after.
--
-- The project has loaded siblings with plain `dofile` since the beginning, and
-- for everything written before now that was fine: a module returning functions
-- and string constants can be built twice with no consequence, because the
-- second copy behaves identically to the first.
--
-- Enums broke that. An enum member is a unique table, and being unique is the
-- entire guarantee -- `value == Hands.cold` is a pointer comparison and nothing
-- else in the process can satisfy it. Load the hands enum twice and there are
-- two `Hands.cold` tables that are not equal to each other. A step built by one
-- caller then fails to index a dispatch table built by another, and the failure
-- reads as "no mechanism for this hand" while the hand is plainly right there.
--
-- So identity-carrying modules need to be loaded exactly once, and this is the
-- thing that guarantees it.
--
-- The loader itself has the same problem one level up: two dofiles of THIS file
-- would build two caches. It sidesteps that through `package.loaded`, which the
-- Lua runtime keeps one of, per process, whatever route reaches it.
--
--     local Load = dofile(neuron_root .. "/src/024-load.lua")
--     local Hands = Load(neuron_root .. "/src/025-enums/027-hands.lua")
--
-- Paths are normalised before they are used as keys, so reaching the same file
-- through `.../025-enums/../025-enums/027-hands.lua` does not produce a second
-- copy of it. That is not a hypothetical -- relative sibling paths built with
-- `..` are exactly how a file inside a subdirectory reaches one outside it.
--------------------------------------------------------------------------------

local CACHE_KEY = "neuron.load"

if package.loaded[CACHE_KEY] then
    return package.loaded[CACHE_KEY]
end

local cache = {}

-- {{{ normalise(path)
-- Collapse `a/b/../c` to `a/c`, and `a/./b` to `a/b`, so that two spellings of
-- one file are one cache key.
--
-- Purely textual. It does not touch the filesystem and does not resolve
-- symlinks -- a file reached through a symlinked directory and through its real
-- path is still two keys. That limit is stated rather than fixed because the
-- fix needs a filesystem library this project does not take a dependency on,
-- and nothing in the tree is reached both ways today.
local function normalise(path)
    local pieces = {}

    for piece in path:gmatch("[^/]+") do
        if piece == ".." and #pieces > 0 and pieces[#pieces] ~= ".." then
            table.remove(pieces)
        elseif piece ~= "." then
            table.insert(pieces, piece)
        end
    end

    local joined = table.concat(pieces, "/")
    return path:sub(1, 1) == "/" and ("/" .. joined) or joined
end
-- }}}

-- Load is a callable table rather than a plain function, so that `loaded()`
-- can hang off it. Callers only ever use the call form.
local Load = setmetatable({}, {})

-- {{{ load_one(path)
-- Run the file at `path` if it has not been run, and return what it returned.
--
-- A file that returns nothing is refused rather than cached as nil, because a
-- nil cache entry is indistinguishable from an absent one and would re-run the
-- file on every call -- which for an enum means new members every time, the
-- exact failure this file exists to prevent, arriving silently.
local function load_one(path)
    local key = normalise(path)

    local cached = cache[key]
    if cached ~= nil then
        return cached
    end

    local chunk, why = loadfile(key)
    if not chunk then
        error(string.format(
            "024-load: cannot load %s\n"
         .. "  %s\n"
         .. "  Loaded as: %s\n"
         .. "  Checked: the file exists and parses. A missing file and a file\n"
         .. "  with a syntax error both arrive here, and the message above says\n"
         .. "  which -- 'No such file' is a path problem, anything else is in\n"
         .. "  the file itself.", path, tostring(why), key), 2)
    end

    local value = chunk()

    if value == nil then
        error(string.format(
            "024-load: %s ran but returned nothing.\n"
         .. "  Every file loaded this way must end with `return <something>`.\n"
         .. "  A file returning nil cannot be cached -- an absent entry and a nil\n"
         .. "  entry look the same -- so it would be re-run on every call, and\n"
         .. "  for anything carrying identity that quietly breaks every\n"
         .. "  comparison against it.", key), 2)
    end

    cache[key] = value
    return value
end
-- }}}

getmetatable(Load).__call = function(_, path) return load_one(path) end

-- {{{ Load.loaded()
-- What has been loaded, for a status board or a test that wants to prove a file
-- was built exactly once.
function Load.loaded()
    local paths = {}
    for path in pairs(cache) do table.insert(paths, path) end
    table.sort(paths)
    return paths
end
-- }}}

package.loaded[CACHE_KEY] = Load

return Load
