--------------------------------------------------------------------------------
-- 070-forget.lua
--
-- `memory.forget` -- a model shortening its own conversation, while it is still
-- having it.
--
-- Every other lever in this project acts on the world. This one acts on the
-- model's own memory, and it exists because a conversation that runs long has
-- exactly two futures: it is cut down, or it stops working. Cutting it down
-- from outside means guessing which parts mattered. The model knows.
--
-- POINTING BY QUOTATION, not by number. A model handed atom numbers would have
-- to keep a mental index of a list it cannot see, and would get it wrong in the
-- ordinary way -- off by one, or citing a number from earlier in the
-- conversation that has since been reused. So it points the way a person
-- points: by saying some of what was there. 069-similarity.lua turns that into
-- one atom, or into a refusal that names the ambiguity.
--
-- ONE AT A TIME, on purpose. A model that can drop five things in one call will
-- drop five things, and the fifth will be something it needed. One call, one
-- atom, one answer telling it what went -- and if it wants another, it asks
-- again with the previous result in front of it.
--
-- FORGETTING IS NOT ITSELF REMEMBERED. The call and its answer are written into
-- the transcript, where a person can read what happened, and they are left OUT
-- of what gets sent back to the model. Otherwise this lever would be absurd:
-- every act of forgetting would add a tool call and a result to the context,
-- and deleting things would make the conversation longer. See
-- 067-transcript.lua's rebuild, which is where that exclusion lives.
--------------------------------------------------------------------------------

local Forget = {}

-- {{{ sibling(neuron_root, filename)
local function sibling(neuron_root, filename)
    return dofile(neuron_root .. "/src/" .. filename)
end
-- }}}

-- {{{ Forget.declaration
Forget.declaration = {
    name    = "memory.forget",
    summary = "Drop one earlier part of this conversation from what you are "
           .. "given next time, by quoting some of it. Use it when the "
           .. "conversation is long and something in it no longer matters. "
           .. "Nothing in the world changes and the record is kept -- only "
           .. "your own memory of it gets shorter.",
    kind    = "internal",
    -- The `none` hand: nothing outside neuron is reached. No database, no
    -- running server, no network. Declaring it explicitly rather than
    -- declaring no hands at all, because an operation with no hands is one
    -- with no way to do anything, and this one does something.
    hands   = { "none" },

    -- The conversation this was spoken in, supplied by the loop rather than by
    -- the model. It is not a parameter the model could get right -- it does not
    -- know its own id and should not have to -- and it is not one it should be
    -- able to get WRONG, because a wrong id would edit somebody else's
    -- conversation.
    needs_conversation = true,

    params  = {
        { name = "quote", type = "string", required = true,
          describes = "Some of what you want dropped, typed from memory. It "
                   .. "does not have to be exact -- close enough to tell it "
                   .. "apart from everything else that was said is enough. If "
                   .. "two parts of the conversation are similar, quote "
                   .. "something that appears in one and not the other." },
        { name = "because", type = "string", required = false,
          describes = "Why it no longer matters. Goes in the record, not in "
                   .. "your memory." },
    },
}
-- }}}

-- {{{ Forget.run(handle, args)
-- Find what was meant, drop it, and say what went.
function Forget.run(handle, args)
    local Transcript = sibling(handle.neuron_root, "067-transcript.lua")
    local Similarity = sibling(handle.neuron_root, "069-similarity.lua")

    local id = args.conversation

    if not id then
        -- Not a nil check standing in for a maybe. The loop supplies this for
        -- any operation declaring `needs_conversation`, so its absence means
        -- this was called from somewhere that does not know what a conversation
        -- is -- the command line, or a test -- and there is nothing sensible to
        -- do with a forget that has no conversation to forget from.
        return nil, "memory.forget can only be used inside a conversation. "
                 .. "There is nothing here for it to shorten."
    end

    -- Only atoms that are still there. Offering an already-dropped one as a
    -- candidate means a model can quote something it has forgotten, which it
    -- cannot -- it is not in front of it any more.
    local candidates = {}

    for _, atom in ipairs(Transcript.atoms(handle, id)) do
        -- The WHOLE atom, not its opening line. Matching against the first
        -- seventy-two characters meant a quotation from the middle of a long
        -- atom scored near zero against the very atom it came out of.
        if atom.state == "kept" then
            table.insert(candidates, { key = atom, text = atom.text })
        end
    end

    -- The instructions are not forgettable. They are section zero, they are
    -- what the model is FOR, and a model that talked itself out of them would
    -- be a model with no idea what it was doing and no way to find out.
    for index = #candidates, 1, -1 do
        for _, marker in ipairs(candidates[index].key.markers) do
            if marker == "system" then table.remove(candidates, index) break end
        end
    end

    -- NOR ANY REQUEST TO FORGET. Every one of them contains a quotation of
    -- something else, which makes it an excellent match for that something
    -- else -- the first attempt matched its own request at eighty-five percent,
    -- beat everything it was actually pointing at, and reported complete
    -- success at having forgotten the act of asking.
    --
    -- Excluding the newest atom alone was not enough: a second request then
    -- matched the FIRST one, for the same reason. It is the whole class that
    -- has to go, and nothing is lost by it -- a request to forget is a sentence
    -- about other text and is never the text somebody meant.
    for index = #candidates, 1, -1 do
        if (candidates[index].text or ""):find(Forget.declaration.name, 1, true)
           or (candidates[index].text or ""):find("memory_forget", 1, true) then
            table.remove(candidates, index)
        end
    end

    if #candidates == 0 then
        return nil, "there is nothing in this conversation to forget yet."
    end

    local best, score = Similarity.best(args.quote, candidates)

    if not best then
        return nil, score
    end

    local atom = best.key

    local ok, trouble = Transcript.prune(handle, id, "drop", { atom.section },
        nil, string.format("the model asked: %s%s",
            tostring(args.quote):gsub("%s+", " "):sub(1, 120),
            args.because and ("  -- " .. args.because) or ""))

    if not ok then
        return nil, trouble
    end

    return {
        section = atom.section,
        describes = string.format(
            "Forgotten. %d characters will not be sent to you again.\n\n"
         .. "  it began   %s\n"
         .. "  matched    %d%% of what you typed\n\n"
         .. "It is still in the written record. Nothing in the world changed.",
            atom.characters, atom.opens, math.floor(score * 100)),
    }
end
-- }}}

return Forget
