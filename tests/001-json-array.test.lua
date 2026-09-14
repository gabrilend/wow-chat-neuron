--------------------------------------------------------------------------------
-- 001-json-array.test.lua
--
-- An empty list must still encode as a list.
--
-- WHY THIS TEST EXISTS: Lua cannot tell {} the empty list from {} the empty
-- record, and this encoder guessed "record". So on a day with no prior
-- conversations the menu received `"conversations": {}`, the page called .map
-- on it, the exception unwound the whole render, and every section BELOW the
-- empty one drew nothing. The receipts, the world count and the entire
-- vocabulary vanished -- and that does not read as a bug, it reads as a system
-- that has forgotten what it can do.
--
-- The guess is now removed at the source: a list says it is a list when it is
-- built, and stays one when it empties out.
--------------------------------------------------------------------------------

local ROOT = "/mnt/mtwo/games/azeroth-core/wow-chat-neuron"
local Json = dofile(ROOT .. "/src/001-json.lua")

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

-- {{{ an unmarked empty table is still a record
-- Not changed. Most empty tables in this project ARE records, and flipping the
-- default would put `[]` where a JSON object belongs.
check("an unmarked empty table encodes as an object",
    Json.encode({}),                                                       "{}")
-- }}}

-- {{{ a marked one is a list, full or empty
check("a marked empty list encodes as a list",
    Json.encode(Json.array()),                                             "[]")

check("a marked list that got something keeps its order",
    Json.encode(Json.array({ 1, 2, 3 })),                             "[1,2,3]")

check("marking an existing list does not disturb it",
    Json.encode(Json.array({ "a", "b" })),                          '["a","b"]')
-- }}}

-- {{{ marking is inherited by nothing
-- The mark is on one table. A list of records does not make the records lists.
check("a nested unmarked empty table is still an object",
    Json.encode(Json.array({ {} })),                                     "[{}]")
-- }}}

-- {{{ the shape the menu actually sends
-- The failing case, written as the page sees it: a state object whose lists are
-- all empty. Every one of these must be `[]` or a section goes blank.
local state = Json.encode({
    conversations = Json.array(),
    receipts      = Json.array(),
    words         = Json.array(),
    keys          = Json.array(),
    services      = Json.array(),
    profiles      = Json.array(),
})

check("an empty menu state has no empty objects in it",
    state:find("{}", 1, true),                                              nil)

check("and reads as six empty lists",
    state,
    '{"conversations":[],"keys":[],"profiles":[],"receipts":[],'
 .. '"services":[],"words":[]}')
-- }}}

-- {{{ the mark survives a second copy of this module
-- sibling() loads with dofile, which re-executes the file, so two parts of the
-- program hold two different copies of the encoder. The mark is recognised by a
-- named field rather than by table identity precisely so that it still means
-- something when the copy that marked a list is not the copy that encodes it.
local Other = dofile(ROOT .. "/src/001-json.lua")

check("a second copy is genuinely a different table",
    rawequal(Other.ARRAY, Json.ARRAY),                                    false)

check("and still encodes the first copy's empty list as a list",
    Other.encode(Json.array()),                                            "[]")

check("both directions",
    Json.encode(Other.array()),                                            "[]")
-- }}}

-- {{{ a round trip
-- Decoding gives back a plain table, which is correct: the mark exists to
-- settle what goes ON the wire, and once it is on the wire the wire says so.
check("an empty list decodes to an empty table",
    type(Json.decode("[]")),                                            "table")
check("with nothing in it",                        #Json.decode("[]"),      0)
-- }}}

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
