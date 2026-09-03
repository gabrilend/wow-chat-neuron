--------------------------------------------------------------------------------
-- 021-chat-router.lua
--
-- Turns a typed sentence into an operation and its arguments.
--
-- THIS IS NOT A PRETEND MODEL, AND IT IS NOT A RIVAL TO ONE. It is the substrate
-- a model will write to. The sibling project put the position exactly right:
-- the AI should write the commands, the player should just ask. Building the
-- commands first, and making them speakable by hand, means a model has something
-- real to aim at rather than an interface invented for it.
--
-- So this is a ROUTER, not a language. A small ordered list of patterns, each
-- mapping a phrasing onto an operation. Anything it does not recognise is handed
-- upward, unchanged, for a model to deal with -- it never guesses.
--
-- See issues/901-the-browser-door.md for the blueprint.
--------------------------------------------------------------------------------

local ChatRouter = {}

-- {{{ normalise(text)
-- Trim, collapse runs of whitespace, and drop a trailing question mark.
--
-- Deliberately NOT lowercased: character names are capitalised and a roster of
-- "Grast,Wenna" must survive intact. Case-insensitivity happens per pattern,
-- where it can be applied to the keywords without touching the arguments.
local function normalise(text)
    return (tostring(text or "")
        :gsub("^%s+", "")
        :gsub("%s+$", "")
        :gsub("%s+", " ")
        :gsub("%s*%?$", ""))
end
-- }}}

-- {{{ PATTERNS
-- Ordered. The first match wins, so more specific phrasings come first.
--
-- Each entry has a Lua pattern, the operation it maps to, and a function turning
-- the captures into arguments. The `changes` flag is what the door uses to
-- decide whether to show a plan and ask before doing anything -- it belongs on
-- the route rather than being inferred from the operation name, so a new route
-- has to state its own blast radius.
local PATTERNS = {
    -- Finding places.
    { match = "^where is (.+)$",            op = "places", changes = false },
    { match = "^where'?s (.+)$",            op = "places", changes = false },
    { match = "^find (.+) place$",          op = "places", changes = false },
    { match = "^places? (.+)$",             op = "places", changes = false },

    -- Finding characters. "who is/are X" and bare "who X".
    { match = "^who a?r?e? ?the (.+)$",     op = "who",    changes = false },
    { match = "^who is (.+)$",              op = "who",    changes = false },
    { match = "^who are (.+)$",             op = "who",    changes = false },
    { match = "^who (.+)$",                 op = "who",    changes = false },
    { match = "^list (.+)$",                op = "who",    changes = false },
    { match = "^show me (.+)$",             op = "who",    changes = false },

    -- Moving. Several phrasings, all landing on the same two arguments.
    { match = "^move (.+) to (.+)$",        op = "teleport", changes = true },
    { match = "^teleport (.+) to (.+)$",    op = "teleport", changes = true },
    { match = "^send (.+) to (.+)$",        op = "teleport", changes = true },
    { match = "^put (.+) on the (.+)$",     op = "teleport", changes = true },
    { match = "^put (.+) at (.+)$",         op = "teleport", changes = true },
    { match = "^put (.+) in (.+)$",         op = "teleport", changes = true },
    { match = "^bring (.+) to (.+)$",       op = "teleport", changes = true },

    -- Undoing.
    { match = "^undo (.+)$",                op = "return", changes = true },
    { match = "^put (.+) back$",            op = "return", changes = true },

    -- Housekeeping.
    { match = "^check$",                    op = "check",    changes = false },
    { match = "^status$",                   op = "status",   changes = false },
    { match = "^what'?s? happening$",       op = "status",   changes = false },
    { match = "^receipts$",                 op = "receipts", changes = false },
    { match = "^what did i do$",            op = "receipts", changes = false },
    { match = "^help$",                     op = "help",     changes = false },
}
-- }}}

-- {{{ ARGUMENT_BUILDERS
-- How each operation turns its captures into named arguments.
--
-- A dispatch table rather than a branch per pattern, so twenty phrasings of
-- "move" all share one builder and adding a twenty-first is one line above.
local ARGUMENT_BUILDERS = {
    places   = function(a)    return { fragment = a } end,
    who      = function(a)    return { roster = a } end,
    teleport = function(a, b) return { roster = a, place = b } end,
    ["return"] = function(a)  return { receipt = a } end,
    check    = function()     return {} end,
    status   = function()     return {} end,
    receipts = function()     return {} end,
    help     = function()     return {} end,
}
-- }}}

-- {{{ ROSTER_SOFTENERS
-- Words people put in front of a roster that the roster resolver would choke on.
--
-- "the hunters" is a roster query with a stray article; "hunters" is a valid one.
-- Stripping these is the difference between the router understanding an ordinary
-- English phrasing and refusing it over a word that carries no meaning here.
--
-- Applied ONLY to roster arguments, never to place names -- "the barrens" is a
-- real place and stripping its article would break the lookup.
local ROSTER_SOFTENERS = {
    "^all of the ", "^all the ", "^all ", "^the ", "^my ", "^every ", "^any ",
}

local function soften_roster(text)
    local softened = text
    for _, prefix in ipairs(ROSTER_SOFTENERS) do
        softened = softened:gsub(prefix, "")
    end
    return softened
end
-- }}}

-- {{{ ChatRouter.route(text)
-- Match a sentence against the vocabulary.
--
-- Two shapes of answer, and the difference matters to the caller:
--
--   recognised -> { op, args, changes, matched }  run it
--   nil        -> the router has no opinion; hand it to a model
--
-- It NEVER guesses. A sentence that half-matches is not routed, because a wrong
-- guess here moves characters somebody did not mean to move.
function ChatRouter.route(text)
    local sentence = normalise(text)
    if sentence == "" then
        return nil
    end

    for _, pattern in ipairs(PATTERNS) do
        -- Keywords match case-insensitively by lowercasing only the part of the
        -- sentence the pattern's literal text covers. Simpler in practice: try
        -- the pattern against a lowercased copy, then take captures from the
        -- ORIGINAL at the same offsets, so "Grast" survives as "Grast".
        local lowered = sentence:lower()
        local from, to = lowered:find(pattern.match)

        if from then
            -- Re-run the match on the lowered copy to get capture positions,
            -- then slice the original text at those positions.
            local captures = { lowered:match(pattern.match) }
            local originals = {}

            for index, capture in ipairs(captures) do
                if type(capture) == "string" then
                    -- Find where this capture sits in the lowered sentence and
                    -- take the same span from the original, preserving case.
                    local at = lowered:find(capture, 1, true)
                    originals[index] = at and sentence:sub(at, at + #capture - 1) or capture
                else
                    originals[index] = capture
                end
            end

            local builder = ARGUMENT_BUILDERS[pattern.op]
            if builder then
                local args = builder(unpack(originals))

                -- Soften only the roster, never the place.
                if args.roster then
                    args.roster = soften_roster(args.roster)
                end

                return {
                    op      = pattern.op,
                    args    = args,
                    changes = pattern.changes,
                    matched = pattern.match,
                }
            end
        end
    end

    return nil
end
-- }}}

-- {{{ ChatRouter.vocabulary()
-- What the router understands, as lines a person can read.
--
-- Returned rather than printed, because two very different callers need it: the
-- help command, and the message shown when a sentence was not understood. The
-- second is the important one -- an error that lists what WOULD have worked is
-- the only thing standing between a person and guessing.
function ChatRouter.vocabulary()
    return {
        { example = "who are the hunters",           does = "resolve a description into characters" },
        { example = "who bots level 18-20",          does = "the same, with a level range" },
        { example = "where is ratchet",              does = "find a named place" },
        { example = "move the hunters to ratchet",   does = "teleport a roster (shows a plan first)" },
        { example = "put Grast on the ratchet dock", does = "the same, for one character" },
        { example = "undo <receipt id>",             does = "put characters back" },
        { example = "receipts",                      does = "what has been done" },
        { example = "check",                         does = "look for leftover rows" },
        { example = "status",                        does = "what is running" },
    }
end
-- }}}

return ChatRouter
