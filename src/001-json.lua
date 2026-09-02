--------------------------------------------------------------------------------
-- 001-json.lua
--
-- Encode and decode JSON. Written here rather than depended on, because this
-- project takes no package-manager dependencies and needs only the subset that
-- receipts and the Claude API actually use.
--
-- Two consumers, and they pull in opposite directions:
--
--   Receipts need ENCODING to be exact and stable. A receipt is the only record
--   of where forty characters used to be standing, so a number that loses
--   precision on the way out is a character who cannot be put back.
--
--   The API needs DECODING to be tolerant of anything a server sends, and
--   needs tool-call arguments parsed rather than string-matched -- escaping in
--   those varies and matching on the serialized form breaks unpredictably.
--
-- Lua's table has no way to distinguish an empty array from an empty object, so
-- an explicit marker is provided for the cases where the difference reaches the
-- wire. Guessing is how a tool call arrives with `{}` where the API wanted `[]`.
--------------------------------------------------------------------------------

local Json = {}

-- {{{ Json.EMPTY_ARRAY
-- A sentinel meaning "an array with nothing in it".
--
-- Without it, `{}` encodes as `{}` (an object), because an empty Lua table looks
-- exactly like an empty Lua table. Every place that must emit `[]` uses this.
Json.EMPTY_ARRAY = setmetatable({}, { __tostring = function() return "[]" end })
-- }}}

-- {{{ ESCAPES
-- The characters JSON requires escaping, as a dispatch table.
--
-- The control characters below 0x20 are handled by the \u form in escape_string
-- rather than being listed individually; only the ones with short forms are
-- here, because the short forms are what a person reading a receipt expects.
local ESCAPES = {
    ['"']    = '\\"',
    ["\\"]   = "\\\\",
    ["\b"]   = "\\b",
    ["\f"]   = "\\f",
    ["\n"]   = "\\n",
    ["\r"]   = "\\r",
    ["\t"]   = "\\t",
}
-- }}}

-- {{{ escape_string(text)
-- Render a Lua string as a JSON string literal, quotes included.
--
-- Control characters that have no short form become \u00XX. Skipping them
-- produces JSON that most parsers accept and some reject, which is the worst
-- kind of output: it works until it is someone else's problem.
local function escape_string(text)
    local escaped = text:gsub('[%z\1-\31\\"]', function(character)
        local short = ESCAPES[character]
        if short then
            return short
        end
        return string.format("\\u%04x", character:byte())
    end)
    return '"' .. escaped .. '"'
end
-- }}}

-- {{{ is_array(value)
-- Decide whether a table should encode as a JSON array or an object.
--
-- The rule: a table with at least one entry, whose keys are exactly the integers
-- 1..n, is an array. Anything else is an object.
--
-- The two paths matter to a reader of the output. A receipt's step list must
-- come out as an array or it stops being ordered, and an ordered thing that
-- silently became unordered is a receipt whose steps cannot be replayed.
local function is_array(value)
    local count = 0
    for _ in pairs(value) do
        count = count + 1
    end
    if count == 0 then
        return false
    end
    for index = 1, count do
        if value[index] == nil then
            return false
        end
    end
    return true
end
-- }}}

-- {{{ encode_number(value)
-- Render a number.
--
-- Integers print as integers; anything else prints with 17 significant digits,
-- which is what a double needs to survive a round trip exactly. A receipt
-- holding a character's position at -3827.93 must reproduce -3827.93 and not
-- -3827.9 -- the difference is a few yards, and a few yards is the difference
-- between a ledge and the ground below it.
--
-- Infinity and NaN have no JSON representation. They are an error rather than
-- being silently written as null, because a null where a coordinate should be
-- is a character who cannot be put back and nothing that says so.
local function encode_number(value)
    if value ~= value then
        error("001-json: cannot encode NaN")
    end
    if value == math.huge or value == -math.huge then
        error("001-json: cannot encode infinity")
    end
    if value == math.floor(value) then
        return string.format("%d", value)
    end
    return string.format("%.17g", value)
end
-- }}}

-- {{{ Json.encode(value, indent)
-- Encode a Lua value. `indent` turns on pretty-printing.
--
-- Receipts are written WITHOUT indent -- one object per line, so the log is
-- append-only in the strict sense that a line is a record. Pretty-printing is
-- for anything a person reads directly.
function Json.encode(value, indent, _depth)
    _depth = _depth or 0

    if value == Json.EMPTY_ARRAY then
        return "[]"
    end

    local kind = type(value)

    if value == nil then
        return "null"
    elseif kind == "boolean" then
        return value and "true" or "false"
    elseif kind == "number" then
        return encode_number(value)
    elseif kind == "string" then
        return escape_string(value)
    elseif kind ~= "table" then
        error("001-json: cannot encode a " .. kind)
    end

    local newline, pad, pad_inner = "", "", ""
    if indent then
        newline   = "\n"
        pad       = string.rep(indent, _depth)
        pad_inner = string.rep(indent, _depth + 1)
    end

    local parts = {}

    if is_array(value) then
        for _, item in ipairs(value) do
            table.insert(parts, pad_inner .. Json.encode(item, indent, _depth + 1))
        end
        if #parts == 0 then
            return "[]"
        end
        return "[" .. newline .. table.concat(parts, "," .. newline) .. newline .. pad .. "]"
    end

    -- Object keys are SORTED. Not for tidiness: an unsorted object makes two
    -- encodings of the same data differ byte-for-byte, which breaks any
    -- comparison, any checksum, and -- in phase 8 -- prompt caching, whose
    -- whole mechanism is a byte-exact prefix match.
    local keys = {}
    for key in pairs(value) do
        if type(key) ~= "string" and type(key) ~= "number" then
            error("001-json: object keys must be strings or numbers, got " .. type(key))
        end
        table.insert(keys, key)
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

    for _, key in ipairs(keys) do
        local encoded_key = escape_string(tostring(key))
        local separator   = indent and ": " or ":"
        table.insert(parts, pad_inner .. encoded_key .. separator
            .. Json.encode(value[key], indent, _depth + 1))
    end

    if #parts == 0 then
        return "{}"
    end
    return "{" .. newline .. table.concat(parts, "," .. newline) .. newline .. pad .. "}"
end
-- }}}

-- {{{ decode helpers
-- A straightforward recursive-descent parser over a string and a position.
-- Every function takes (text, position) and returns (value, next_position).

local decode_value  -- forward declaration; the grammar is mutually recursive

local function skip_whitespace(text, position)
    local _, stop = text:find("^[ \t\r\n]*", position)
    return stop + 1
end

local function decode_error(text, position, expected)
    local line = 1
    for _ in text:sub(1, position):gmatch("\n") do line = line + 1 end
    error(string.format("001-json: at byte %d (line %d): expected %s, found %q",
        position, line, expected, text:sub(position, position + 12)))
end

local UNESCAPES = {
    ['"'] = '"', ["\\"] = "\\", ["/"] = "/",
    b = "\b", f = "\f", n = "\n", r = "\r", t = "\t",
}

local function decode_string(text, position)
    if text:sub(position, position) ~= '"' then
        decode_error(text, position, "a string")
    end
    position = position + 1

    local parts = {}
    while true do
        local character = text:sub(position, position)
        if character == "" then
            decode_error(text, position, "a closing quote")
        elseif character == '"' then
            return table.concat(parts), position + 1
        elseif character == "\\" then
            local code = text:sub(position + 1, position + 1)
            local simple = UNESCAPES[code]
            if simple then
                table.insert(parts, simple)
                position = position + 2
            elseif code == "u" then
                local hex = text:sub(position + 2, position + 5)
                local point = tonumber(hex, 16)
                if not point then
                    decode_error(text, position, "four hex digits after \\u")
                end
                -- Encode as UTF-8. Surrogate pairs are NOT recombined: a
                -- character above the basic plane arrives as two escapes and
                -- comes out as two three-byte sequences. Nothing this project
                -- reads has ever contained one, and pretending to handle it
                -- would be worse than saying so here.
                if point < 0x80 then
                    table.insert(parts, string.char(point))
                elseif point < 0x800 then
                    table.insert(parts, string.char(
                        0xC0 + math.floor(point / 0x40),
                        0x80 + (point % 0x40)))
                else
                    table.insert(parts, string.char(
                        0xE0 + math.floor(point / 0x1000),
                        0x80 + (math.floor(point / 0x40) % 0x40),
                        0x80 + (point % 0x40)))
                end
                position = position + 6
            else
                decode_error(text, position, "a valid escape")
            end
        else
            local stop = text:find('[%z\1-\31\\"]', position)
            table.insert(parts, text:sub(position, (stop or #text + 1) - 1))
            position = stop or (#text + 1)
        end
    end
end

local function decode_array(text, position)
    position = skip_whitespace(text, position + 1)
    local items = {}

    if text:sub(position, position) == "]" then
        return items, position + 1
    end

    while true do
        local item
        item, position = decode_value(text, position)
        table.insert(items, item)
        position = skip_whitespace(text, position)

        local character = text:sub(position, position)
        if character == "]" then
            return items, position + 1
        elseif character == "," then
            position = skip_whitespace(text, position + 1)
        else
            decode_error(text, position, "',' or ']'")
        end
    end
end

local function decode_object(text, position)
    position = skip_whitespace(text, position + 1)
    local object = {}

    if text:sub(position, position) == "}" then
        return object, position + 1
    end

    while true do
        local key
        key, position = decode_string(text, position)
        position = skip_whitespace(text, position)

        if text:sub(position, position) ~= ":" then
            decode_error(text, position, "':'")
        end
        position = skip_whitespace(text, position + 1)

        local value
        value, position = decode_value(text, position)
        object[key] = value
        position = skip_whitespace(text, position)

        local character = text:sub(position, position)
        if character == "}" then
            return object, position + 1
        elseif character == "," then
            position = skip_whitespace(text, position + 1)
        else
            decode_error(text, position, "',' or '}'")
        end
    end
end

decode_value = function(text, position)
    position = skip_whitespace(text, position)
    local character = text:sub(position, position)

    if character == "{" then
        return decode_object(text, position)
    elseif character == "[" then
        return decode_array(text, position)
    elseif character == '"' then
        return decode_string(text, position)
    elseif text:sub(position, position + 3) == "true" then
        return true, position + 4
    elseif text:sub(position, position + 4) == "false" then
        return false, position + 5
    elseif text:sub(position, position + 3) == "null" then
        -- null becomes nil, which means a key whose value was null VANISHES
        -- from the decoded table. That is the correct Lua shape and it is worth
        -- knowing about: a caller distinguishing "absent" from "explicitly
        -- null" cannot do it after decoding.
        return nil, position + 4
    end

    local number_text = text:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", position)
    if number_text and #number_text > 0 then
        local number = tonumber(number_text)
        if number then
            return number, position + #number_text
        end
    end

    decode_error(text, position, "a value")
end
-- }}}

-- {{{ Json.decode(text)
-- Parse a JSON document. Returns the value, or nil plus a message.
--
-- Errors are RETURNED rather than thrown, because the main consumer is a
-- response from a network service and a malformed one is an ordinary event to
-- be reported, not an exceptional one to crash on.
function Json.decode(text)
    if type(text) ~= "string" then
        return nil, "001-json: decode wants a string, got " .. type(text)
    end

    local ok, value, position = pcall(decode_value, text, 1)
    if not ok then
        return nil, tostring(value)
    end

    position = skip_whitespace(text, position)
    if position <= #text then
        return nil, string.format(
            "001-json: trailing content after the value, at byte %d: %q",
            position, text:sub(position, position + 20))
    end

    return value
end
-- }}}

return Json
