--------------------------------------------------------------------------------
-- 025-enum.lua
--
-- A closed, ordered set of named members, where a member is a unique table
-- rather than a string.
--
-- The reason for the whole file is one sentence: routing should work by knowing
-- exactly which one was ours. A string cannot say where it came from. Given
-- "cold" there is no way to ask whether it is a hand or a word that wandered in
-- from somewhere else, so every comparison against it is a bet that two people
-- typed the same letters. A member is a table with an identity, so
-- `value == Hands.cold` is a pointer comparison that nothing else in the
-- process can accidentally satisfy, and `Hands.holds(value)` answers the
-- question a dispatcher actually asks.
--
-- Members are immutable through a proxy: the table handed out is empty, all
-- reads go through __index into hidden storage, and all writes hit a __newindex
-- that refuses. A member whose name could be reassigned is a member that can be
-- made to lie, and the guarantee above rests on that being impossible.
--------------------------------------------------------------------------------

local Enum = {}

-- {{{ freeze(fields, description, extra_metamethods)
-- Wrap a table of fields so it can be read and not written.
--
-- The handed-out table is EMPTY. That is load-bearing: __newindex only fires
-- for keys a table does not already have, so a table carrying its own fields
-- would let every one of them be silently overwritten. Storage lives behind
-- __index instead, where assignment cannot reach it.
--
-- __metatable is set so nothing can retrieve or replace the metatable and undo
-- any of this.
local function freeze(fields, description, extra)
    local metatable = {
        __index = fields,
        __newindex = function(_, key)
            error(string.format(
                "%s is immutable; cannot set '%s'.\n"
             .. "  Enum members and enums are built once and never change. If you\n"
             .. "  are trying to attach data to a member, put it in the member's\n"
             .. "  definition where every reader can see it.",
                description, tostring(key)), 2)
        end,
        __metatable = "locked",
    }

    for name, implementation in pairs(extra or {}) do
        metatable[name] = implementation
    end

    return setmetatable({}, metatable)
end
-- }}}

-- {{{ Enum.define(enum_name, definitions)
-- Build an enum.
--
-- definitions is an ordered array. Each entry is a table whose first positional
-- element is the member's name; every other key becomes a field on the member,
-- so an enum can carry per-member data -- a class's colour, a slot's number --
-- in the same place the member is declared rather than in a parallel table that
-- can fall out of step with it.
--
--     local Hands = Enum.define("Hands", {
--         { "cold",     summary = "a database write" },
--         { "live",     summary = "a game master command over SOAP" },
--     })
--
--     Hands.cold          the member
--     Hands.cold.name     "cold"
--     Hands.cold.index    1
--     Hands.cold.enum     Hands
--     Hands.cold.summary  "a database write"
function Enum.define(enum_name, definitions)
    if type(enum_name) ~= "string" or enum_name == "" then
        error("Enum.define: an enum needs a name, and the name is what appears "
           .. "in every refusal this enum produces.", 2)
    end

    if type(definitions) ~= "table" or #definitions == 0 then
        error(string.format(
            "Enum.define(%s): an enum with no members is a closed set that\n"
         .. "  closes over nothing. Nothing can ever be one of these.",
            enum_name), 2)
    end

    local members  = {}   -- ordered, for iteration and for printing
    local by_name  = {}   -- for `of`, which is the boundary crossing
    local enum                                        -- forward; members hold it

    for index, definition in ipairs(definitions) do
        local member_name = definition[1]

        if type(member_name) ~= "string" or member_name == "" then
            error(string.format(
                "Enum.define(%s): member %d has no name. The first positional\n"
             .. "  element of each definition is the member's name.",
                enum_name, index), 2)
        end

        if by_name[member_name] then
            error(string.format(
                "Enum.define(%s): '%s' is defined twice, at positions %d and %d.\n"
             .. "  Two members with one name means one of them can never be\n"
             .. "  reached through `of`, and which one is an accident of order.",
                enum_name, member_name, by_name[member_name].index, index), 2)
        end

        local fields = { name = member_name, index = index }

        for key, value in pairs(definition) do
            if key ~= 1 then fields[key] = value end
        end

        -- The back-reference is filled after the enum table exists. It is the
        -- field `holds` reads, and it is why a member from another enum with
        -- the same name is still distinguishable from one of ours.
        fields.enum = nil

        local member = freeze(fields, enum_name .. "." .. member_name, {
            __tostring = function() return member_name end,
        })

        members[index]        = member
        by_name[member_name]  = member
        by_name[member_name .. "\0fields"] = fields   -- kept for the back-fill
    end

    -- {{{ names()
    local function names()
        local list = {}
        for index, member in ipairs(members) do list[index] = member.name end
        return list
    end
    -- }}}

    -- {{{ holds(value)
    -- Is this one of ours? The only honest way to ask.
    local function holds(value)
        return type(value) == "table" and rawequal(value.enum, enum)
    end
    -- }}}

    -- {{{ of(text)
    -- The boundary crossing. Text from a terminal, from JSON, or from a database
    -- column becomes a member exactly once, here, and everything inward of this
    -- point compares by identity.
    --
    -- A member passed back in is refused rather than returned. It means the
    -- caller has lost track of whether it holds text or a member, and letting it
    -- through makes the boundary fuzzy in exactly the place its whole value is
    -- that it is sharp.
    local function of(text)
        if holds(text) then
            return nil, string.format(
                "%s.of was given %s.%s, which is already a member of this enum.\n"
             .. "  Conversion happens once, where text enters. Passing a member\n"
             .. "  back in means somewhere upstream has stopped knowing whether\n"
             .. "  it is holding text or a member -- find that place instead.",
                enum_name, enum_name, tostring(text))
        end

        if type(text) ~= "string" then
            return nil, string.format(
                "%s.of wanted the name of a member and got a %s (%s).\n"
             .. "  The members are: %s.",
                enum_name, type(text), tostring(text),
                table.concat(names(), ", "))
        end

        local member = by_name[text]
        if member then return member end

        -- Near matches first, then the whole set. A caller who typed "res" for
        -- "resident" is helped by the prefix line; a caller who typed something
        -- unrelated needs the full list, and both are cheap at these sizes.
        local near = {}
        local lowered = text:lower()
        for _, candidate in ipairs(members) do
            local candidate_lowered = candidate.name:lower()
            if candidate_lowered:sub(1, #lowered) == lowered
            or lowered:sub(1, #candidate_lowered) == candidate_lowered then
                table.insert(near, candidate.name)
            end
        end

        local message = string.format("'%s' is not a member of %s.", text, enum_name)

        if #near > 0 then
            message = message .. string.format("\n  Did you mean: %s?",
                table.concat(near, ", "))
        end

        message = message .. string.format("\n  The members are: %s.",
            table.concat(names(), ", "))

        return nil, message
    end
    -- }}}

    local enum_fields = {
        name    = enum_name,
        members = members,
        of      = of,
        holds   = holds,
        names   = names,
    }

    for _, member in ipairs(members) do
        enum_fields[member.name] = member
    end

    enum = freeze(enum_fields, "enum " .. enum_name, {
        __tostring = function() return enum_name end,
        -- Iterating an enum should walk its members in order. Without this a
        -- reader reaches for pairs(), gets the functions mixed in with the
        -- members, and writes a loop that quietly includes `of`.
        __len  = function() return #members end,
        __call = function(_, text) return of(text) end,
    })

    -- Back-fill the enum reference into each member's hidden storage. It cannot
    -- be done earlier because the enum did not exist, and it cannot be done
    -- through the member because the member refuses writes -- which is the
    -- point of the member.
    for _, member in ipairs(members) do
        by_name[member.name .. "\0fields"].enum = enum
        by_name[member.name .. "\0fields"] = nil
    end

    return enum
end
-- }}}

-- {{{ Enum.name_of(value)
-- The name, for anything on its way out to text -- a receipt, a JSON body, a
-- SQL bind, a printed line.
--
-- This exists because of a trap. A member is an EMPTY proxy table, so handing
-- one to the JSON encoder produces `{}` rather than `"cold"`, silently, and a
-- receipt written that way is a receipt that has forgotten which hand did the
-- work. Anything crossing back out to text goes through here.
function Enum.name_of(value)
    if type(value) == "table" and type(value.name) == "string"
    and type(value.enum) == "table" then
        return value.name
    end

    error(string.format(
        "Enum.name_of was given a %s (%s), which is not an enum member.\n"
     .. "  This function exists for the trip back out to text -- receipts, JSON,\n"
     .. "  SQL binds. If the value is already a plain string, it does not need\n"
     .. "  converting; if it is something else, find where it stopped being a\n"
     .. "  member.", type(value), tostring(value)), 2)
end
-- }}}

return Enum
