--------------------------------------------------------------------------------
-- 069-similarity.lua
--
-- Which piece of text did somebody mean, when they typed it from memory?
--
-- A model that wants to forget part of its own conversation has to say WHICH
-- part, and the only thing it has to point with is words. It will not quote
-- exactly. It will paraphrase, drop a clause, misremember a number, and
-- occasionally emit a run of junk characters in the middle of an otherwise
-- correct sentence. Matching on equality answers "no such thing" to all of
-- those, which is the same as having no feature.
--
-- WHY CHARACTER TRIGRAMS, and not the two obvious alternatives:
--
--   Matching by PREFIX breaks the moment anything is inserted. Five stray
--   characters early in the quotation displace everything after them, and a
--   prefix comparison sees a mismatch from that point to the end -- so a
--   quotation that is ninety-five percent right scores as badly as one that is
--   wrong.
--
--   Edit distance handles insertion correctly and costs the product of the two
--   lengths. Against a conversation of a dozen atoms of a few thousand
--   characters each, asked on every tool call, that is real time spent for an
--   answer trigrams give in one pass.
--
-- A trigram is any three consecutive characters. Insertion damages only the
-- handful of trigrams that straddle it; everything before and after is
-- untouched, because a trigram has no idea where in the string it came from.
-- That positionlessness is exactly the property that makes displacement stop
-- mattering.
--
-- THE SCORE is containment, not similarity: how much of what was TYPED appears
-- in the candidate. Not symmetric, and deliberately. Somebody quoting thirty
-- characters of a two-thousand-character atom has quoted it correctly, and a
-- symmetric measure would score that pairing at almost nothing because the
-- lengths are so different.
--
-- REFUSING IS A RESULT. When the best candidate is not clearly better than the
-- second, this says so and names both rather than picking. Deleting the wrong
-- piece of a conversation is silent and unrecoverable from inside the
-- conversation, and "which of these two did you mean" costs one more sentence.
--------------------------------------------------------------------------------

local Similarity = {}

-- {{{ MARGIN / FLOOR
-- What counts as a clear answer.
--
-- FLOOR: below this the best candidate is not a match at all, it is merely the
-- least bad. A third of the typed trigrams present is already generous for a
-- real quotation and hopeless for an invented one.
--
-- MARGIN: the best must beat the second by this much of a fraction. Two atoms
-- in one conversation genuinely can be near-identical -- the same question
-- asked twice, the same table fetched twice -- and picking between them on a
-- hundredth of a point is picking at random with extra steps.
Similarity.FLOOR  = 0.34
Similarity.MARGIN = 0.10
-- }}}

-- {{{ normalise(text)
-- Case folded, runs of whitespace collapsed to one space.
--
-- Both are differences a person or a model introduces without meaning
-- anything by them: a quotation retyped from memory has different line breaks
-- and different capitalisation, and neither says anything about whether it is
-- the same passage.
local function normalise(text)
    return (tostring(text or ""):lower():gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end
-- }}}

-- {{{ trigrams(text)
-- Every three consecutive characters, as a set.
--
-- A SET rather than a list, so a phrase repeated inside one atom does not count
-- twice. The question is "does this appear here", and it appears or it does
-- not.
--
-- Text shorter than three characters has no trigrams and therefore matches
-- nothing. That is the correct answer: two characters do not identify a passage
-- and pretending they might is how the wrong thing gets deleted.
local function trigrams(text)
    local found, count = {}, 0
    local flat = normalise(text)

    for index = 1, #flat - 2 do
        local gram = flat:sub(index, index + 2)
        if not found[gram] then
            found[gram] = true
            count = count + 1
        end
    end

    return found, count
end
-- }}}

-- {{{ Similarity.score(typed, candidate)
-- What fraction of the typed text's trigrams appear in the candidate.
--
-- Zero to one. One means every three-character run of the quotation occurs
-- somewhere in the candidate, which for anything longer than a phrase means it
-- is that passage.
function Similarity.score(typed, candidate)
    local wanted, total = trigrams(typed)
    if total == 0 then return 0 end

    local have = trigrams(candidate)

    local hits = 0
    for gram in pairs(wanted) do
        if have[gram] then hits = hits + 1 end
    end

    return hits / total
end
-- }}}

-- {{{ Similarity.best(typed, candidates)
-- The one that was meant, or a refusal saying why not.
--
-- `candidates` is a list of { key = anything, text = "..." }. The key is handed
-- back untouched, so a caller can put an atom number, a filename or a whole
-- object in it and get the same thing back.
--
-- Returns: the winning candidate, its score, the runner-up
--      or: nil, a sentence explaining which of the two ways it failed.
function Similarity.best(typed, candidates)
    if #normalise(typed) < 3 then
        return nil, "too little to go on: '" .. tostring(typed) .. "'.\n"
                 .. "  Three characters cannot identify a passage. Quote enough "
                 .. "of it to tell it apart from everything else that was said."
    end

    local scored = {}
    for _, candidate in ipairs(candidates) do
        table.insert(scored, {
            key   = candidate.key,
            text  = candidate.text,
            score = Similarity.score(typed, candidate.text),
        })
    end

    if #scored == 0 then
        return nil, "there is nothing to match against."
    end

    table.sort(scored, function(a, b) return a.score > b.score end)

    local best   = scored[1]
    local second = scored[2]

    if best.score < Similarity.FLOOR then
        return nil, string.format(
            "nothing here resembles that. The closest was %d%% of what you "
         .. "typed and the floor is %d%%.\n"
         .. "  Quote something that was actually said, from the conversation "
         .. "above.",
            math.floor(best.score * 100), math.floor(Similarity.FLOOR * 100))
    end

    if second and (best.score - second.score) < Similarity.MARGIN then
        return nil, string.format(
            "that matches two things about equally well -- %d%% and %d%% -- so "
         .. "it is not clear which was meant.\n"
         .. "  The first begins: %s\n"
         .. "  The second begins: %s\n"
         .. "  Quote something that appears in one and not the other.",
            math.floor(best.score * 100), math.floor(second.score * 100),
            (normalise(best.text)):sub(1, 60),
            (normalise(second.text)):sub(1, 60))
    end

    return best, best.score, second
end
-- }}}

return Similarity
