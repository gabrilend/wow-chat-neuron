--------------------------------------------------------------------------------
-- 054-stubs.lua
--
-- A path that works and is not the thing, and says so every time it is used.
--
-- There is a shape of incompleteness this project has no word for yet. A
-- fallback is forbidden -- a warning is an error and silently doing the second
-- best thing is how somebody spends an afternoon. But a STUB is different: it
-- is the deliberate placeholder you build so the rest of the system can be
-- exercised before the hard part exists. Prototyping "change that goblin" with
-- models the game already ships is not a fallback. It is the only way to build
-- everything around the part nobody has written.
--
-- What makes it honest rather than a lie is that it announces itself. Not in a
-- comment somebody will not read, and not once in a design document -- at the
-- point of use, in the plan a person agrees to, and in the receipt afterwards.
--
--     [ STUB ] picking a creature's appearance
--       doing        using a display the game already ships
--       instead of   finding one on open-game-art and converting it
--       go build it  issues/1203-the-asset-scrapers.md
--
-- Declared at module scope and noticed at point of use, so that every stub in
-- the project can be listed without running anything -- which turns the
-- mechanism into a to-do list generated from the code rather than kept beside
-- it.
--------------------------------------------------------------------------------

local Stubs = {}

-- {{{ DECLARED
-- Every stub built in this process, in declaration order.
--
-- Process-global rather than per-module, so `scripts/stubs` can load the tree
-- and print the lot. A stub nobody can enumerate is a stub that gets forgotten
-- in exactly the way this file exists to prevent.
local DECLARED = {}
-- }}}

-- {{{ Stubs.declare(specification)
-- Name a placeholder. Returns the stub, which is what gets noticed later.
--
--   what        the job being done, in a person's words
--   doing       what this actually does
--   instead_of  what it is standing in for
--   issue       the file to go and work on
--
-- All four are required. A stub missing `issue` is a stub with nowhere to send
-- somebody, which is the whole point -- the announcement is useless if it does
-- not say where to go, and "somewhere in the issues directory" is not a place.
function Stubs.declare(specification)
    for _, required in ipairs({ "what", "doing", "instead_of", "issue" }) do
        if type(specification[required]) ~= "string"
        or specification[required] == "" then
            error(string.format(
                "Stubs.declare: missing `%s`.\n"
             .. "  A stub says four things: what job it is doing, what it\n"
             .. "  actually does, what it stands in for, and which issue file to\n"
             .. "  go and work on. Any of them missing makes the announcement\n"
             .. "  something a reader cannot act on, and an announcement nobody\n"
             .. "  can act on is a comment.", required), 2)
        end
    end

    local stub = {
        what       = specification.what,
        doing      = specification.doing,
        instead_of = specification.instead_of,
        issue      = specification.issue,
        used       = 0,
        announced  = false,
    }

    table.insert(DECLARED, stub)

    -- {{{ stub:describe()
    -- The block a person reads. Goes into plan descriptions and receipts, so
    -- agreeing to something built on a stub means having been told.
    function stub:describe()
        return table.concat({
            "[ STUB ] " .. self.what,
            "  doing        " .. self.doing,
            "  instead of   " .. self.instead_of,
            "  go build it  issues/" .. self.issue,
        }, "\n")
    end
    -- }}}

    -- {{{ stub:notice()
    -- Mark it used, and say so on the terminal the FIRST time only.
    --
    -- Once per process, because a plan that spawns forty creatures would
    -- otherwise print the same four lines forty times and teach everybody to
    -- ignore it. The count is kept and reported by `Stubs.summary`, so the
    -- fortieth use is not lost -- it is just not shouted.
    function stub:notice()
        self.used = self.used + 1

        if not self.announced then
            self.announced = true
            io.stderr:write("\n" .. self:describe() .. "\n\n")
        end

        return self:describe()
    end
    -- }}}

    return stub
end
-- }}}

-- {{{ Stubs.declared()
-- Every stub built in this process, whether or not it was used.
function Stubs.declared()
    return DECLARED
end
-- }}}

-- {{{ Stubs.used()
-- Only the ones that actually ran, with counts. What belongs at the end of a
-- run: not "here is everything unfinished" but "here is what you just leaned
-- on".
function Stubs.used()
    local leaned_on = {}
    for _, stub in ipairs(DECLARED) do
        if stub.used > 0 then table.insert(leaned_on, stub) end
    end
    return leaned_on
end
-- }}}

-- {{{ Stubs.summary()
-- One block for the end of a run, or nil when nothing was stubbed.
--
-- nil rather than an empty string, so a caller writes it or does not without
-- having to check whether it is worth writing.
function Stubs.summary()
    local leaned_on = Stubs.used()
    if #leaned_on == 0 then return nil end

    local lines = { "", "This run leaned on " .. #leaned_on
        .. (#leaned_on == 1 and " placeholder:" or " placeholders:") }

    for _, stub in ipairs(leaned_on) do
        table.insert(lines, string.format("  %-44s %d time%s   issues/%s",
            stub.what, stub.used, stub.used == 1 and "" or "s", stub.issue))
    end

    table.insert(lines,
        "Each one works and is not the thing. The issue files say what it should be.")

    return table.concat(lines, "\n")
end
-- }}}

return Stubs
