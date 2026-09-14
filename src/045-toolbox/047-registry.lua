--------------------------------------------------------------------------------
-- 047-registry.lua
--
-- Every word neuron knows, in one table, keyed by name.
--
-- Until now an operation was reachable only because 020-cli.lua had a function
-- that knew about it: seven hand-written subcommands, each importing its file,
-- each calling plan and apply in that operation's own idiom. Nothing could
-- enumerate them, so nothing could print the set, hand it to a model, or refuse
-- an unknown name with a list of the real ones.
--
-- A registry is a dispatch table -- one hash index to find a word, not a walk
-- down a chain of comparisons -- and it is also the only object in the project
-- that can answer "what can this thing do", which is the question every other
-- surface is built out of.
--
-- Validation happens at define time and is deliberately harsh. An operation
-- half-declared is found when the registry is built, once, at startup; the
-- alternative is finding it the first time somebody asks for that word, which
-- is later and further from the mistake and quite possibly in front of a model
-- that will now try something else instead.
--------------------------------------------------------------------------------

local here = debug.getinfo(1, "S").source:match("^@(.*/)")
local Load = dofile(here .. "../024-load.lua")

local Hands = Load(here .. "../025-enums/027-hands.lua")
local Kinds = Load(here .. "../025-enums/028-kinds.lua")
local Types = Load(here .. "046-types.lua")

local Registry = {}

Registry.Hands = Hands
Registry.Kinds = Kinds
Registry.Types = Types

-- {{{ OPERATION_FILES
-- Where the words live. Listed rather than discovered, because a directory scan
-- makes the set of operations depend on what happens to be lying in a folder --
-- and a half-finished operation file dropped in during a refactor would join the
-- vocabulary silently.
local VOCABULARIES = {}

VOCABULARIES.world = {
    "018-bestiary.lua",
    "013-teleport.lua",
    "014-return.lua",
    -- The deleted queue, not the permanent erase. 015-retire.lua is
    -- `character.purge` now and is in NO vocabulary: something that cannot be
    -- undone should need the sort of deliberation a conversation does not have.
    { file = "071-shelve.lua", field = "Retire"  },
    { file = "071-shelve.lua", field = "Restore" },
    "049-spawn.lua",
    -- TEMPORARY. A test lever, to prove the pipeline end to end. Delete the
    -- file and this line together. See 061-broadcast.lua.
    "061-broadcast.lua",
    -- The model shortening its own memory. In BOTH vocabularies, because a
    -- conversation running long is a property of conversations rather than of
    -- what is being talked about.
    "070-forget.lua",
}

-- The levers for configuring where thinking is sent. A SEPARATE vocabulary,
-- not a filtered view of the one above.
--
-- Two tables rather than one with a filter, because a filter is a rule somebody
-- can get wrong and two tables are two tables. The model that adjusts the
-- inference configuration must not be able to teleport anybody, and the model
-- running the world must not be able to point neuron somewhere else
-- mid-sentence.
--
-- Each entry names its module and the field inside it, because one file holds
-- several of these -- they are small and belong together.
VOCABULARIES.asking = {
    { file = "062-asking-levers.lua", field = "Status"   },
    { file = "062-asking-levers.lua", field = "Check"    },
    { file = "062-asking-levers.lua", field = "Endpoint" },
    { file = "062-asking-levers.lua", field = "Model"    },
    { file = "062-asking-levers.lua", field = "Timeout"  },
    -- Reading the project. The configuration window exists for when something
    -- is wrong, and what is wrong is very often in the code rather than in a
    -- setting -- a model that can read the file can name the line.
    { file = "064-source-levers.lua",  field = "List"     },
    { file = "064-source-levers.lua",  field = "Read"     },
    -- Credentials: existence and replacement, never reading. See 065 for why
    -- that split is the design rather than a compromise.
    { file = "065-secret-levers.lua",  field = "Status"   },
    { file = "065-secret-levers.lua",  field = "Write"    },
    { file = "065-secret-levers.lua",  field = "Clear"    },
    -- The same lever as the world vocabulary carries. A configuration
    -- conversation runs on a small model with a small context, so it is the
    -- one that needs this soonest.
    "070-forget.lua",
}

Registry.VOCABULARIES = VOCABULARIES
-- }}}

-- {{{ check_name(name)
-- subject.verb, and the subject is what is being acted on rather than the
-- machinery doing it: character.teleport, not teleport, not move.character, not
-- cold.reposition. Sorting the registry then sorts by what is being touched,
-- which is how somebody actually looks for a word -- they know what they want
-- to change before they know the verb.
local function check_name(name)
    if type(name) ~= "string" then
        return nil, "an operation's name must be a string, got " .. type(name)
    end

    local subject, verb = name:match("^([a-z][a-z_]*)%.([a-z][a-z_]*)$")

    if not subject then
        return nil, string.format(
            "'%s' is not a usable operation name.\n"
         .. "  Names are subject.verb, lower case, underscores allowed inside\n"
         .. "  each half: character.teleport, world.spawn, party.assemble.\n"
         .. "  The subject is what is being acted on, never the machinery doing\n"
         .. "  it -- so character.teleport rather than cold.reposition, because\n"
         .. "  sorting by subject is how somebody finds a word they half-know.",
            name)
    end

    return subject, verb
end
-- }}}

-- {{{ check_params(name, params)
local function check_params(name, params)
    if params == nil then return {} end

    if type(params) ~= "table" then
        return nil, string.format("%s: params must be a list, got %s",
            name, type(params))
    end

    local checked, seen = {}, {}

    for index, parameter in ipairs(params) do
        if type(parameter.name) ~= "string" then
            return nil, string.format(
                "%s: parameter %d has no name.\n"
             .. "  The name is the command-line flag AND the JSON Schema\n"
             .. "  property, so a parameter without one exists on neither\n"
             .. "  surface.", name, index)
        end

        if seen[parameter.name] then
            return nil, string.format(
                "%s: two parameters are both called '%s'.\n"
             .. "  On the command line the second would shadow the first; in a\n"
             .. "  schema one of them simply would not exist.",
                name, parameter.name)
        end
        seen[parameter.name] = true

        local kind, why = Types.of(parameter.type)
        if not kind then
            return nil, string.format("%s, parameter '%s': %s",
                name, parameter.name, why)
        end

        -- A parameter with no prose is a parameter a model cannot choose. The
        -- describes field is the sentence it reads when deciding whether this
        -- is the word it wants, and it is the only thing telling it that a
        -- roster may be a query rather than a name.
        if type(parameter.describes) ~= "string" or #parameter.describes < 10 then
            return nil, string.format(
                "%s: parameter '%s' has no useful description.\n"
             .. "  This string is what a model reads when it is filling the\n"
             .. "  argument in, and it is the ONLY thing that can teach it that\n"
             .. "  a roster may be a query rather than a name. \"the roster\"\n"
             .. "  teaches nothing; an example of the query language teaches the\n"
             .. "  whole feature.", name, parameter.name)
        end

        table.insert(checked, {
            name      = parameter.name,
            type      = kind,
            required  = parameter.required and true or false,
            default   = parameter.default,
            describes = parameter.describes,
        })
    end

    return checked
end
-- }}}

-- {{{ Registry.define(declaration, implementation)
-- Turn a declaration into a registered operation, or refuse it.
function Registry.define(declaration, implementation)
    local name = declaration.name

    local subject, verb = check_name(name)
    if not subject then return nil, verb end

    if type(declaration.summary) ~= "string" or #declaration.summary < 10 then
        return nil, string.format(
            "%s has no useful summary.\n"
         .. "  It is the one line a person reads in the command list and the\n"
         .. "  description a model reads when choosing between words.", name)
    end

    local kind, kind_why = Kinds.of(declaration.kind)
    if not kind then return nil, name .. ": " .. kind_why end

    -- Hands arrive as strings in a declaration -- that is the boundary where
    -- text becomes members, and after it everything compares by identity.
    local hands = {}
    for index, spelling in ipairs(declaration.hands or {}) do
        local hand, hand_why = Hands.of(spelling)
        if not hand then
            return nil, string.format("%s, hand %d: %s", name, index, hand_why)
        end
        table.insert(hands, hand)
    end

    if #hands == 0 then
        return nil, string.format(
            "%s declares no hands, so there is no way for it to reach anything.\n"
         .. "  An operation that genuinely touches nothing -- a catalogue, an\n"
         .. "  explanation -- declares the `none` hand rather than an empty\n"
         .. "  list, so that the dispatcher routes it the ordinary way instead\n"
         .. "  of checking for a special case.", name)
    end

    local params, params_why = check_params(name, declaration.params)
    if not params then return nil, params_why end

    -- The kind says which functions must exist. A `read` supplies `run`; a
    -- `change` or a `final` supplies `plan` and `apply`. Checking here is what
    -- makes `kind` a switch rather than a label.
    implementation = implementation or {}

    for _, required in ipairs(kind.declares) do
        if type(implementation[required]) ~= "function" then
            return nil, string.format(
                "%s is declared '%s' and must supply %s, which is missing.\n"
             .. "  A '%s' operation supplies: %s.\n"
             .. "  %s", name, kind.name, required, kind.name,
                table.concat(kind.declares, " and "), kind.summary)
        end
    end

    -- Anything final must offer a confirmation, and it must be OPTIONAL. If it
    -- were required, a model would fill it with true on the first attempt and
    -- the gate would be decorative. Optional means the model has to be told no
    -- once -- which means saying out loud what it is about to do, while
    -- somebody is reading.
    if kind.needs_confirm then
        local confirm
        for _, parameter in ipairs(params) do
            if parameter.name == "confirm" then confirm = parameter end
        end

        if not confirm then
            return nil, string.format(
                "%s cannot be undone and offers no way to confirm it.\n"
             .. "  Every 'final' operation takes a `confirm` boolean. This is\n"
             .. "  not politeness -- the parameter appearing in the schema is\n"
             .. "  what stops a model reaching an irreversible word in one step.",
                name)
        end

        if confirm.required then
            return nil, string.format(
                "%s makes `confirm` required, which makes the gate decorative.\n"
             .. "  A required confirmation is one a model fills in with true on\n"
             .. "  its first attempt, because the schema told it to. Optional\n"
             .. "  means it must be refused once and say what it is about to do.",
                name)
        end
    end

    return {
        name      = name,
        subject   = subject,
        verb      = verb,
        summary   = declaration.summary,
        kind      = kind,
        hands     = hands,
        params    = params,
        plan      = implementation.plan,
        apply     = implementation.apply,
        run       = implementation.run,
        describe_plan = implementation.describe_plan,
        -- Whether the dispatcher supplies the conversation this was spoken in.
        --
        -- Declared, not inferred. An operation that acts on the conversation
        -- rather than on the world needs to know which one, and it must not be
        -- something the model can name: a wrong id edits somebody else's
        -- conversation, and a model does not know its own.
        needs_conversation = declaration.needs_conversation or false,
        -- Which optional AzerothCore modules this word requires to work at all.
        --
        -- Declared rather than discovered, and empty for almost everything: the
        -- cold hand reaches the database, which every deployment has. A word
        -- listing one here is a word that is simply absent on a server built
        -- without that module -- see 072-addons.lua for why absent beats
        -- present-and-broken.
        needs = declaration.needs or {},
    }
end
-- }}}

-- {{{ Registry.load(neuron_root)
-- Build the whole set, refusing at the first bad word.
function Registry.load(neuron_root, which)
    which = which or "world"

    local listed = VOCABULARIES[which]

    if not listed then
        local known = {}
        for name in pairs(VOCABULARIES) do table.insert(known, name) end
        table.sort(known)
        return nil, string.format(
            "there is no '%s' vocabulary. neuron has: %s.",
            tostring(which), table.concat(known, ", "))
    end

    local by_name, ordered = {}, {}

    for _, entry in ipairs(listed) do
        local file   = type(entry) == "table" and entry.file or entry
        local loaded = Load(neuron_root .. "/src/" .. file)
        local module = type(entry) == "table" and loaded[entry.field] or loaded

        if not module or not module.declaration then
            return nil, string.format(
                "%s is listed as an operation and declares nothing.\n"
             .. "  Every operation file returns a module with a `declaration`\n"
             .. "  table on it. A file without one is either not an operation or\n"
             .. "  is half-written.", file)
        end

        local operation, why = Registry.define(module.declaration, module)
        if not operation then
            return nil, string.format("in %s:\n  %s", file, why)
        end

        if by_name[operation.name] then
            return nil, string.format(
                "'%s' is declared twice, in %s and again in %s.\n"
             .. "  One of them can never be reached, and which is an accident of\n"
             .. "  file order.", operation.name,
                by_name[operation.name].file, file)
        end

        operation.file = file
        by_name[operation.name] = operation
        table.insert(ordered, operation)
    end

    -- Sorted by name, which sorts by subject, which groups every word that
    -- touches a character together.
    table.sort(ordered, function(a, b) return a.name < b.name end)

    return {
        vocabulary = which,
        by_name = by_name,
        ordered = ordered,

        -- {{{ of(name)
        -- The boundary a model's tool call crosses. A name that is not here is
        -- the end of the road for that request, so the refusal has to carry
        -- what WOULD have worked -- it is the only thing telling a model what
        -- exists.
        of = function(name)
            local found = by_name[name]
            if found then return found end

            local near, subject = {}, tostring(name):match("^([a-z_]+)%.")
            for _, operation in ipairs(ordered) do
                if subject and operation.subject == subject then
                    table.insert(near, operation.name)
                end
            end

            local message = string.format("'%s' is not an operation.", tostring(name))

            if #near > 0 then
                message = message .. string.format(
                    "\n  Words about %s: %s", subject, table.concat(near, ", "))
            end

            local all = {}
            for _, operation in ipairs(ordered) do table.insert(all, operation.name) end

            return nil, message .. "\n  Everything neuron knows: "
                .. table.concat(all, ", ")
        end,
        -- }}}

        -- {{{ subjects()
        subjects = function()
            local seen, list = {}, {}
            for _, operation in ipairs(ordered) do
                if not seen[operation.subject] then
                    seen[operation.subject] = true
                    table.insert(list, operation.subject)
                end
            end
            return list
        end,
        -- }}}
    }
end
-- }}}

-- {{{ Registry.usage(operation)
-- The command line for one word, built from its declaration rather than written.
--
-- --plan is added here rather than declared by each operation, because every
-- word that changes anything gets it and none of them should have to ask.
function Registry.usage(operation)
    local pieces = { "neuron", operation.verb }

    for _, parameter in ipairs(operation.params) do
        local flag = string.format("--%s <%s>", parameter.name, parameter.type.short)
        table.insert(pieces, parameter.required and flag or ("[" .. flag .. "]"))
    end

    if operation.kind.writes_receipt then
        table.insert(pieces, "[--plan]")
    end

    return table.concat(pieces, " ")
end
-- }}}

return Registry
