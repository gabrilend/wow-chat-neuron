--------------------------------------------------------------------------------
-- 074-overrides.lua
--
-- Writing one line of `config/deployment.lua`.
--
-- Everything neuron works out for itself can be stated instead, and stating it
-- has to be possible from the page rather than only from an editor -- somebody
-- whose deployment is shaped unusually is exactly the person who cannot yet get
-- neuron running well enough to ask it for help.
--
-- EDITED IN PLACE, never rewritten. The file is mostly comments explaining what
-- each setting is for and what nil means, and a generated file would lose all of
-- it the first time somebody used a button. So this finds the line, replaces
-- what is after the `=`, and leaves every character around it alone.
--
-- Anchored on eight spaces, which is the indent inside the `overrides` block.
-- The same anchoring discipline as the asking config's rewriter, and for the
-- same reason: a pattern matching any indentation edits whichever copy of the
-- name it reaches first, silently, and the setting somebody asked to change
-- stays as it was while a different one moves.
--------------------------------------------------------------------------------

local Overrides = {}

-- {{{ Overrides.path(handle)
function Overrides.path(handle)
    return handle.neuron_root .. "/config/deployment.lua"
end
-- }}}

-- {{{ Overrides.set(handle, key, value)
-- Replace one override's value. `value` of nil clears it back to detection.
--
-- Returns true, or nil and a sentence saying what stopped it.
function Overrides.set(handle, key, value)
    local path = Overrides.path(handle)

    local file = io.open(path, "r")
    if not file then
        return nil, "config/deployment.lua is not there to edit."
    end

    local text = file:read("*a")
    file:close()

    local at = text:find("\n    overrides%s*=%s*{")
    if not at then
        return nil, "config/deployment.lua has no overrides block, so there is "
                 .. "nowhere to write this. It is the table where every value "
                 .. "neuron works out for itself can be stated instead."
    end

    local head, tail = text:sub(1, at - 1), text:sub(at)

    -- nil, not the string "nil": clearing an override means going back to
    -- detection, and a quoted "nil" would be a path called nil.
    local rendered = (value == nil or value == "")
        and "nil" or string.format("%q", tostring(value))

    local pattern = "(\n        " .. key .. "%s*=%s*)([^,\n]*)(,)"
    local changed, count = tail:gsub(pattern, function(before, was, after)
        return before .. rendered .. after
    end, 1)

    if count == 0 then
        return nil, string.format(
            "the overrides block has no line for '%s'.\n"
         .. "  This edits an existing line rather than adding one, so the "
         .. "comment above it -- which says what the setting is for and what "
         .. "nil means -- stays attached to it.", key)
    end

    local out = io.open(path, "w")
    if not out then
        return nil, "config/deployment.lua could not be written."
    end
    out:write(head .. changed)
    out:close()

    return true
end
-- }}}

-- {{{ Overrides.readable_dir(path)
-- Is this a directory something can be read out of?
--
-- Checked before it is written, because an override that points nowhere is
-- worse than no override: detection would have found something, and now it is
-- skipped in favour of a path that has nothing behind it.
function Overrides.readable_dir(path)
    local probe = io.popen(string.format("test -d %s && echo yes",
        "'" .. tostring(path):gsub("'", "'\\''") .. "'"), "r")

    if not probe then return false end

    local answer = probe:read("*l")
    probe:close()

    return answer == "yes"
end
-- }}}

-- {{{ Overrides.executable(path)
function Overrides.executable(path)
    local probe = io.popen(string.format("test -x %s && echo yes",
        "'" .. tostring(path):gsub("'", "'\\''") .. "'"), "r")

    if not probe then return false end

    local answer = probe:read("*l")
    probe:close()

    return answer == "yes"
end
-- }}}

return Overrides
