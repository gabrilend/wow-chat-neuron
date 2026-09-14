--------------------------------------------------------------------------------
-- tests/001-json.test.lua
--
-- The cases that matter for the two consumers: exact round-tripping of the
-- numbers a receipt holds, and tolerant parsing of what a server sends.
--------------------------------------------------------------------------------

local Json = dofile("/mnt/mtwo/games/azeroth-core/wow-chat-neuron/src/001-json.lua")

local passed, failed = 0, 0

local function check(label, got, want)
    if got == want then passed = passed + 1 else
        failed = failed + 1
        print(string.format("FAIL  %s\n        got  %s\n        want %s",
            label, tostring(got), tostring(want)))
    end
end

local function check_error(label, fn)
    local ok = pcall(fn)
    if ok then failed = failed + 1; print("FAIL  " .. label .. " (expected an error)")
    else passed = passed + 1 end
end

-- Encoding scalars
check("integer",        Json.encode(42), "42")
check("negative",       Json.encode(-91), "-91")
check("large guid",     Json.encode(12345678), "12345678")
check("true",           Json.encode(true), "true")
check("false",          Json.encode(false), "false")
check("string",         Json.encode("Grast"), '"Grast"')
check("empty string",   Json.encode(""), '""')
check("quote in name",  Json.encode('say "hi"'), '"say \\"hi\\""')
check("backslash",      Json.encode("a\\b"), '"a\\\\b"')
check("newline",        Json.encode("a\nb"), '"a\\nb"')
check("tab",            Json.encode("a\tb"), '"a\\tb"')
check("control char",   Json.encode("a\1b"), '"a\\u0001b"')

-- The property a receipt depends on: a coordinate survives a round trip exactly.
local coordinate = -3827.93
local round_tripped = Json.decode(Json.encode(coordinate))
check("coordinate round trip is exact", round_tripped, coordinate)

local awkward = 0.1 + 0.2
check("awkward float round trip", Json.decode(Json.encode(awkward)), awkward)

check_error("NaN refuses",      function() Json.encode(0/0) end)
check_error("infinity refuses", function() Json.encode(math.huge) end)

-- Arrays and objects
check("array",        Json.encode({1, 2, 3}), "[1,2,3]")
check("empty table is an object", Json.encode({}), "{}")
check("a marked empty list",      Json.encode(Json.array()),     "[]")
check("object",       Json.encode({name = "Grast"}), '{"name":"Grast"}')

-- Keys are sorted, so two encodings of the same data are byte-identical.
-- Phase 8's prompt caching is a byte-exact prefix match; unsorted keys would
-- silently destroy the cache hit rate with nothing to see.
check("keys sort",
    Json.encode({zebra = 1, alpha = 2, middle = 3}),
    '{"alpha":2,"middle":3,"zebra":1}')

-- Nesting, which is the shape of a receipt
check("nested",
    Json.encode({steps = {{hand = "cold"}, {hand = "live"}}}),
    '{"steps":[{"hand":"cold"},{"hand":"live"}]}')

-- Decoding
check("decode integer",  Json.decode("42"), 42)
check("decode float",    Json.decode("-3827.93"), -3827.93)
check("decode exponent", Json.decode("1.5e3"), 1500)
check("decode true",     Json.decode("true"), true)
check("decode string",   Json.decode('"Grast"'), "Grast")
check("decode escapes",  Json.decode('"a\\nb"'), "a\nb")
check("decode unicode escape", Json.decode('"\\u0041"'), "A")

local decoded = Json.decode('{"a":1,"b":[2,3]}')
check("decode object field", decoded.a, 1)
check("decode nested array", decoded.b[2], 3)

local empty_array = Json.decode("[]")
check("decode empty array length", #empty_array, 0)

-- Malformed input is REPORTED, not thrown -- the main consumer is a network
-- response, where malformed is ordinary rather than exceptional.
local bad, why = Json.decode("{oops}")
check("malformed returns nil", bad, nil)
check("malformed explains itself", type(why), "string")

local trailing = Json.decode('{"a":1} extra')
check("trailing content rejected", trailing, nil)

-- A realistic tool-call argument block, which is what phase 8 parses.
local tool_input = Json.decode('{"roster":"my-party","place":"ratchet","dry_run":false}')
check("tool arg string", tool_input.roster, "my-party")
check("tool arg boolean", tool_input.dry_run, false)

print(string.format("\n001-json: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
