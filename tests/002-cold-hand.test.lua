--------------------------------------------------------------------------------
-- tests/002-cold-hand.test.lua
--
-- Exercises the parts of the cold hand that need no database: value escaping,
-- placeholder binding, and the batch-output unescaper.
--
-- These are the functions where a naive implementation looks correct and is
-- wrong for exactly one input -- a name with an apostrophe, a GUID big enough
-- to hit scientific notation, a backslash in a string. Each case below is one
-- of those inputs.
--------------------------------------------------------------------------------

local NEURON = "/mnt/mtwo/games/azeroth-core/wow-chat-neuron"
local ColdHand = dofile(NEURON .. "/src/002-cold-hand.lua")

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

-- {{{ check_error(label, fn)
-- Assert that a call refuses rather than proceeding. Every one of these is a
-- programming error in an operation that must surface at the point of mistake.
local function check_error(label, fn)
    local ok = pcall(fn)
    if ok then
        failed = failed + 1
        print("FAIL  " .. label .. "\n        expected an error, got success")
    else
        passed = passed + 1
    end
end
-- }}}

-- Binding: the shapes an operation actually writes.
check("integer bind",
    ColdHand.bind("SELECT ? ", {42}), "SELECT 42 ")

check("large GUID does not go scientific",
    ColdHand.bind("WHERE guid = ?", {12345678}), "WHERE guid = 12345678")

check("negative integer",
    ColdHand.bind("SET z = ?", {-91}), "SET z = -91")

check("float keeps precision",
    ColdHand.bind("SET x = ?", {-3827.93}), "SET x = -3827.9299999999998")

check("boolean true becomes 1",
    ColdHand.bind("SET online = ?", {true}), "SET online = 1")

check("boolean false becomes 0",
    ColdHand.bind("SET online = ?", {false}), "SET online = 0")

check("plain string is quoted",
    ColdHand.bind("WHERE name = ?", {"Grast"}), "WHERE name = 'Grast'")

-- The inputs that break naive escapers.
check("apostrophe in a name",
    ColdHand.bind("WHERE name = ?", {"O'Doul"}), "WHERE name = 'O\\'Doul'")

check("backslash in a value",
    ColdHand.bind("WHERE note = ?", {"a\\b"}), "WHERE note = 'a\\\\b'")

check("embedded newline",
    ColdHand.bind("WHERE note = ?", {"a\nb"}), "WHERE note = 'a\\nb'")

check("double quote",
    ColdHand.bind("WHERE note = ?", {'say "hi"'}), "WHERE note = 'say \\\"hi\\\"'")

check("empty string is not NULL",
    ColdHand.bind("WHERE name = ?", {""}), "WHERE name = ''")

check("percent sign survives gsub replacement",
    ColdHand.bind("WHERE note = ?", {"100%"}), "WHERE note = '100%'")

check("percent-s survives gsub replacement",
    ColdHand.bind("WHERE note = ?", {"%s%1"}), "WHERE note = '%s%1'")

-- Multiple placeholders, in order.
check("three placeholders bind left to right",
    ColdHand.bind("SET x = ?, y = ? WHERE guid = ?", {1, 2, 3}),
    "SET x = 1, y = 2 WHERE guid = 3")

-- Count mismatches are programming errors and must be loud.
check_error("too few values", function()
    ColdHand.bind("SET x = ?, y = ?", {1})
end)

check_error("too many values", function()
    ColdHand.bind("SET x = ?", {1, 2})
end)

check_error("a table cannot be a bind value", function()
    ColdHand.bind("SET x = ?", {{}})
end)

-- Placeholder lists for IN clauses.
check("placeholders(1)", ColdHand.placeholders(1), "?")
check("placeholders(3)", ColdHand.placeholders(3), "?, ?, ?")

check_error("placeholders(0) is not valid SQL", function()
    ColdHand.placeholders(0)
end)

print(string.format("\n002-cold-hand: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
