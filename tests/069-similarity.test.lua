--------------------------------------------------------------------------------
-- 069-similarity.test.lua
--
-- Pointing at a passage by typing it from memory.
--
-- The failure this guards against is silent and unrecoverable from inside a
-- conversation: a model asks to forget one thing, the matcher picks another,
-- and the answer reports complete success. So the tests are mostly about the
-- cases where it should REFUSE.
--------------------------------------------------------------------------------

local ROOT       = "/mnt/mtwo/games/azeroth-core/wow-chat-neuron"
local Similarity = dofile(ROOT .. "/src/069-similarity.lua")

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

local POOL = {
    { key = "undead",  text = "what undead creatures are there around level twelve" },
    { key = "hunters", text = "please move every hunter bot to ratchet" },
    { key = "table",   text = "entry 299 ghoul level 11, entry 1501 skeleton level 13" },
}

-- {{{ an exact quotation
local best, score = Similarity.best(
    "what undead creatures are there around level twelve", POOL)
check("finds the passage",                             best.key,   "undead")
check("at full score",                                    score,          1)
-- }}}

-- {{{ a paraphrase
best, score = Similarity.best("undead creatures around level 12", POOL)
check("a paraphrase still finds it",                   best.key,   "undead")
check("and says how sure it is",                 score > 0.8,         true)
-- }}}

-- {{{ junk inserted in the middle
-- The case that rules out prefix matching. Five stray characters displace
-- everything after them, and a prefix comparison sees a mismatch from there to
-- the end -- so a quotation that is almost entirely right scores as badly as
-- one that is wrong. A trigram has no idea where in the string it came from.
best, score = Similarity.best(
    "what undead creaFFFFFtures are there around level twelve", POOL)
check("insertion does not displace the match",         best.key,   "undead")
check("and barely moves the score",              score > 0.85,        true)
-- }}}

-- {{{ case and whitespace mean nothing
best = Similarity.best("PLEASE   MOVE\n\nEVERY HUNTER BOT to Ratchet", POOL)
check("case folded, whitespace collapsed",            best.key,  "hunters")
-- }}}

-- {{{ quoting the middle of a passage
-- A model quotes what it remembers, which is rarely the beginning.
best = Similarity.best("1501 skeleton level 13", POOL)
check("the middle identifies it too",                   best.key,   "table")
-- }}}

-- {{{ refusing: nothing resembles it
local nothing, why = Similarity.best("elephants in the department of trade", POOL)
check("an invented quotation is refused",               nothing,        nil)
check("and says the closest was too far",
    why:find("resembles that", 1, true) ~= nil,                       true)
-- }}}

-- {{{ refusing: two things equally well
-- Two atoms in one conversation genuinely can be near-identical -- the same
-- question asked twice, the same table fetched twice. Picking between them on a
-- hundredth of a point is picking at random with extra steps.
local twins = {
    { key = "first",  text = "what undead are there around level twelve" },
    { key = "second", text = "what undead are there around level twelve" },
}

nothing, why = Similarity.best("what undead are there around level twelve", twins)
check("an ambiguous quotation is refused",              nothing,        nil)
check("and both are named",
    why:find("two things", 1, true) ~= nil,                           true)
-- }}}

-- {{{ refusing: too little to go on
nothing, why = Similarity.best("ab", POOL)
check("two characters cannot identify anything",        nothing,        nil)
check("and it says why",
    why:find("too little to go on", 1, true) ~= nil,                  true)
-- }}}

-- {{{ containment, not similarity
-- A short quotation from a long passage has quoted it correctly. A symmetric
-- measure would score that pairing near zero because the lengths differ so
-- much, which is the wrong answer to the question actually being asked.
local long = { { key = "long", text = string.rep("filler text here. ", 200)
                                   .. "the one distinctive sentence" } }

best, score = Similarity.best("the one distinctive sentence", long)
check("a short quotation of a long passage matches",     best.key,  "long")
check("at full score",                                      score,      1)
-- }}}

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
