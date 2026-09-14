--------------------------------------------------------------------------------
-- 019-vocabulary.lua
--
-- The closed set of words neuron knows, and the renderer that prints it as an
-- eighty-column table.
--
-- Two halves, deliberately separated. The DECLARATIONS half is data: one entry
-- per operation, carrying the same fields the real declarations carry in
-- 013-teleport.lua, 014-return.lua and 015-retire.lua. The RENDER half turns
-- any list of that shape into the document at docs/vocabulary.txt.
--
-- Right now the data half is a sketch -- forty-two operations, of which three
-- are built. That is on purpose: the set has to make sense as a whole before
-- most of it exists, because names that sort together and parameters that mean
-- the same thing everywhere are decisions you cannot make one operation at a
-- time. Issue 701 builds the registry; issue 705 points this renderer at it and
-- deletes the sketch. The output does not change shape when that happens, which
-- is how you will know the sketch was honest.
--
-- Run through scripts/vocabulary.
--------------------------------------------------------------------------------

local neuron_root = ...
local output_path = select(2, ...)
if output_path == "" then output_path = nil end  -- --stdout arrives as an empty path

-- The hands and the kinds are not this file's to define. They are enums, and
-- reading them here means a sketch entry naming a hand that does not exist is
-- caught while the table is being drawn rather than surviving into a document
-- that then teaches somebody the wrong word.
local Load  = dofile(neuron_root .. "/src/024-load.lua")
local Hands = Load(neuron_root .. "/src/025-enums/027-hands.lua")
local Kinds = Load(neuron_root .. "/src/025-enums/028-kinds.lua")

--------------------------------------------------------------------------------
-- DECLARATIONS
--------------------------------------------------------------------------------

-- {{{ SECTIONS
-- Grouped by the phase that builds them, because that is also the order in
-- which each group becomes speakable, and a reader wanting to know what neuron
-- can do TODAY reads down until the ground stops being solid.
--
-- Fields per entry, matching the live declarations:
--   name    what the operation is called, everywhere
--   hands   reach, in preference order; first one that is up wins
--   kind    "read" | "change" | "final"  -- see the legend
--   params  ordered {name, type, "?" when optional}
local SECTIONS = {

{ title = "READING THE WORLD",
  phase = "phase 1 -- Reach",
  note  = {
    "Nothing here alters anything, which is why it is first and why every one",
    "of these is safe to hand a model without a gate in front of it. These are",
    "also the words a person reaches for immediately before a word that does",
    "change something: seeing who a roster resolves to is how somebody avoids",
    "moving the wrong forty characters.",
  },
  entries = {
  { name = "world.status",       hands = {"cold","live"}, kind = "read",
    params = {} },
  { name = "world.places",       hands = {"cold"},        kind = "read",
    params = { {"fragment","str","?"}, {"limit","int","?"} } },
  { name = "world.roster",       hands = {"cold"},        kind = "read",
    params = { {"roster","rost"}, {"limit","int","?"}, {"orphans","bool","?"} } },
  { name = "world.character",    hands = {"cold"},        kind = "read",
    params = { {"character","str"} } },
  { name = "world.groups",       hands = {"cold"},        kind = "read",
    params = { {"roster","rost","?"} } },
  { name = "world.online",       hands = {"live"},        kind = "read",
    params = {} },
  { name = "world.dangling",     hands = {"cold"},        kind = "read",
    params = {} },
  { name = "world.receipts",     hands = {"cold"},        kind = "read",
    params = { {"date","str","?"}, {"operation","str","?"}, {"limit","int","?"} } },
  -- BUILT. The first read to carry a declaration, and so the first word a model
  -- can use to look at anything rather than change it. See 018-bestiary.lua.
  { name = "world.creatures",    hands = {"cold"},        kind = "read",
    params = { {"type","str","?"}, {"level","int","?"}, {"name","str","?"},
               {"rank","str","?"}, {"limit","int","?"} } },
  } },

{ title = "DISPLACEMENT",
  phase = "phase 2 -- Anyone can be anywhere",
  note  = {
    "Position is four numbers and a map. Every word here writes all five or",
    "refuses, because coordinates without the map put a character at the right",
    "numbers on the wrong continent, which looks exactly like nothing having",
    "happened. All of these are reversible because all of them capture where",
    "everybody was standing before they moved.",
  },
  entries = {
  { name = "character.teleport", hands = {"live","cold"}, kind = "change",
    params = { {"roster","rost"}, {"place","plac"} } },
  { name = "character.scatter",  hands = {"live","cold"}, kind = "change",
    params = { {"roster","rost"}, {"place","plac"}, {"radius","int","?"},
               {"shape","str","?"} } },
  { name = "character.summon",   hands = {"live"},        kind = "change",
    params = { {"roster","rost"}, {"target","str"} } },
  { name = "character.homebind", hands = {"cold"},        kind = "change",
    params = { {"roster","rost"}, {"place","plac"} } },
  { name = "character.return",   hands = {"cold"},        kind = "change",
    params = { {"receipt","rcpt"} } },
  } },

{ title = "OUTFITTING",
  phase = "phase 3 -- Anyone can be wearing anything",
  note  = {
    "Taking gear away and putting it back are two words, not one word with a",
    "direction flag, because the putting-back reads a receipt and the taking",
    "away writes one. What strip removes goes into holding rather than being",
    "destroyed, which is the only reason reclothe can exist at all.",
  },
  entries = {
  { name = "item.lists",         hands = {"cold"},        kind = "read",
    params = { {"fragment","str","?"} } },
  { name = "character.strip",    hands = {"cold"},        kind = "change",
    params = { {"roster","rost"}, {"slots","list","?"} } },
  { name = "character.equip",    hands = {"cold"},        kind = "change",
    params = { {"roster","rost"}, {"items","item"} } },
  { name = "character.give",     hands = {"live","cold"}, kind = "change",
    params = { {"roster","rost"}, {"item","str"}, {"count","int","?"} } },
  { name = "character.money",    hands = {"cold"},        kind = "change",
    params = { {"roster","rost"}, {"copper","int"} } },
  { name = "character.reclothe", hands = {"cold"},        kind = "change",
    params = { {"receipt","rcpt"} } },
  } },

{ title = "COMPANY",
  phase = "phase 4 -- Nobody is alone",
  note  = {
    "A group is a thing that outlives its members: the garrison holds a place",
    "rather than holding a list of characters, so a guard who dies is replaced",
    "without the post being re-declared. Retiring characters is the one word in",
    "this section that nothing can undo, and it is marked accordingly.",
  },
  entries = {
  { name = "party.assemble",     hands = {"live","cold"}, kind = "change",
    params = { {"roster","rost"}, {"leader","str","?"} } },
  { name = "party.disband",      hands = {"live","cold"}, kind = "change",
    params = { {"roster","rost"} } },
  { name = "character.generate", hands = {"cold"},        kind = "change",
    params = { {"count","int"}, {"class","str","?"}, {"level","int","?"},
               {"faction","str","?"} } },
  { name = "garrison.post",      hands = {"resident","cold"},  kind = "change",
    params = { {"roster","rost"}, {"place","plac"}, {"spacing","int","?"} } },
  { name = "garrison.recall",    hands = {"resident","cold"},  kind = "change",
    params = { {"place","plac"} } },
  { name = "character.retire",   hands = {"cold"},        kind = "final",
    params = { {"roster","rost"}, {"confirm","bool","?"} } },
  } },

{ title = "RENEWAL",
  phase = "phase 5 -- Change without replacement",
  note  = {
    "A character who is levelled is still the same character; a character who",
    "is deleted and remade is not, and everything that referred to them now",
    "refers to nobody. That distinction is the whole phase. Reclass is marked",
    "final because a class change discards talents, spells and gear the old",
    "class could hold and the new one cannot.",
  },
  entries = {
  { name = "character.level",    hands = {"live","cold"}, kind = "change",
    params = { {"roster","rost"}, {"level","int"} } },
  { name = "character.respec",   hands = {"live","cold"}, kind = "change",
    params = { {"roster","rost"} } },
  { name = "character.rename",   hands = {"cold"},        kind = "change",
    params = { {"character","str"}, {"name","str"} } },
  { name = "character.restyle",  hands = {"cold"},        kind = "change",
    params = { {"roster","rost"}, {"vector","str"} } },
  { name = "character.reclass",  hands = {"cold"},        kind = "final",
    params = { {"character","str"}, {"class","str"}, {"confirm","bool","?"} } },
  } },

{ title = "CONSTRUCTION",
  phase = "phase 6 -- Architecture the map files never had",
  note  = {
    "Geometry placed by hand: a wall is a row of the same object at a spacing",
    "somebody chose. These take the resident hand first because a structure",
    "that appears while people are standing in it is the point, and fall back",
    "to cold so a build survives the world being down.",
  },
  entries = {
  { name = "structure.build",    hands = {"resident","cold"},  kind = "change",
    params = { {"blueprint","str"}, {"place","plac"}, {"facing","int","?"} } },
  { name = "structure.remove",   hands = {"resident","cold"},  kind = "change",
    params = { {"receipt","rcpt"} } },
  -- BUILT. Live cannot do this at all: .npc add spawns at the caller's own
  -- position and a SOAP caller has no body. See 049-spawn.lua.
  { name = "world.spawn",        hands = {"resident","cold"}, kind = "change",
    params = { {"creature","int"}, {"place","plac"}, {"count","int","?"},
               {"spread","int","?"}, {"permanent","bool","?"} } },
  { name = "world.clear",        hands = {"cold"},        kind = "final",
    params = { {"map","str"}, {"confirm","bool","?"} } },
  } },

{ title = "THE TOOLBOX ITSELF",
  phase = "phase 7 -- The vocabulary is a thing you can hold",
  note  = {
    "Neuron answering about neuron. These take no hand at all -- the world is",
    "not touched and does not need to be up. They exist because a model that",
    "picks a word that does not exist has to be told what does, and a list of",
    "near matches in an error message is the only thing standing between it",
    "and guessing again.",
  },
  entries = {
  { name = "neuron.catalogue",   hands = {"none"},        kind = "read",
    params = { {"section","str","?"}, {"format","str","?"} } },
  { name = "neuron.explain",     hands = {"none"},        kind = "read",
    params = { {"operation","str"} } },
  } },

{ title = "NARRATION",
  phase = "phase 10 -- Changes become story",
  note  = {
    "A receipt is a record; a story is a record somebody wants to read. These",
    "read the receipt log and nothing else, which is why they are safe and why",
    "they work with the world down. The voice parameter selects a register,",
    "not a set of facts -- the facts are whatever the receipt says.",
  },
  entries = {
  { name = "story.receipt",      hands = {"cold"},        kind = "read",
    params = { {"receipt","rcpt"}, {"voice","str","?"} } },
  { name = "story.session",      hands = {"cold"},        kind = "read",
    params = { {"date","str","?"}, {"voice","str","?"} } },
  { name = "story.character",    hands = {"cold"},        kind = "read",
    params = { {"character","str"}, {"voice","str","?"} } },
  } },

{ title = "PORTAGE",
  phase = "phase 11 -- What was made here can be made again",
  note  = {
    "The deployment is not neuron's to build, so exporting it is exporting a",
    "description of what was done to it rather than a copy of it. Import is",
    "final because it writes over a world that already has characters in it,",
    "and there is no receipt for a world you have not read yet.",
  },
  entries = {
  { name = "deployment.check",   hands = {"cold","live"}, kind = "read",
    params = {} },
  { name = "deployment.export",  hands = {"cold"},        kind = "read",
    params = { {"path","str"}, {"parts","list","?"} } },
  { name = "deployment.import",  hands = {"cold"},        kind = "final",
    params = { {"path","str"}, {"confirm","bool","?"} } },
  } },

}
-- }}}

--------------------------------------------------------------------------------
-- RENDER
--------------------------------------------------------------------------------

-- {{{ WIDTH
-- Eighty columns, spent deliberately. The name gets the most because it is what
-- a reader scans down; the parameters get the rest because a word without its
-- arguments is not a declaration, it is a wish.
local WIDTH       = 80
local NAME_WIDTH  = 21
local HANDS_WIDTH =  9
local PARAM_START = 36  -- name 21 + gap 1 + hands 9 + gap 1 + kind 1 + gap 2
-- }}}

-- {{{ glyph_for(entry)
-- One character, because the column is one character wide and because three
-- states is the whole truth: it reads, it can be put back, it cannot.
--
-- The character comes off the Kinds enum rather than a table here, so the
-- document and the code that will enforce these kinds cannot disagree about
-- which glyph means which.
local function glyph_for(entry)
    local kind, why = Kinds.of(entry.kind)
    if not kind then
        io.stderr:write(string.format(
            "019-vocabulary: %s declares kind '%s'.\n  %s\n",
            entry.name, tostring(entry.kind), why))
        os.exit(1)
    end
    return kind.glyph
end
-- }}}

-- {{{ hands_for(entry)
-- Every hand named in the sketch, checked against the enum, and printed as
-- the enum's own abbreviation. A hand spelled 'res' instead of 'resident'
-- would otherwise render perfectly and route nowhere the day the sketch
-- becomes a registry -- which is precisely what this caught on its first run.
local function hands_for(entry)
    local names = {}
    for _, spelling in ipairs(entry.hands) do
        local hand, why = Hands.of(spelling)
        if not hand then
            io.stderr:write(string.format(
                "019-vocabulary: %s declares hand '%s'.\n  %s\n",
                entry.name, tostring(spelling), why))
            os.exit(1)
        end
        table.insert(names, hand.short)
    end
    return table.concat(names, " ")
end
-- }}}

local lines = {}

-- {{{ emit(text)
local function emit(text)
    text = text or ""
    if #text > WIDTH then
        io.stderr:write(string.format(
            "019-vocabulary: a line ran to %d columns, past the %d this document\n"
         .. "  promises. The line was:\n    %s\n"
         .. "  Nothing was written. Shorten the entry or widen WIDTH -- but the\n"
         .. "  width is the point, so shorten the entry.\n",
            #text, WIDTH, text))
        os.exit(1)
    end
    table.insert(lines, text)
end
-- }}}

-- {{{ rule(character)
local function rule(character)
    emit(string.rep(character, WIDTH))
end
-- }}}

-- {{{ render_params(params)
-- "roster:rost place:plac limit:int?" -- name, colon, type, and a question mark
-- when the argument may be left out. Optionality is shown on the parameter
-- rather than in a separate column because the reader's question is always
-- "must I give this one", asked about one parameter at a time.
local function render_params(params)
    if #params == 0 then return "--" end

    local pieces = {}
    for _, parameter in ipairs(params) do
        table.insert(pieces,
            parameter[1] .. ":" .. parameter[2] .. (parameter[3] or ""))
    end
    return table.concat(pieces, " ")
end
-- }}}

-- {{{ render_row(entry)
-- One word as one line -- or two, when its parameters do not fit.
--
-- The wrap is not a concession. A word with five optional arguments is a real
-- word, and the alternatives were both worse: dropping a parameter makes the
-- table lie about the vocabulary, and widening the column means narrowing the
-- name column, which is already exactly as wide as the longest name.
--
-- The continuation is indented to the parameter column and carries nothing
-- else, so a reader scanning down the name column sees one entry per name and a
-- reader scanning the parameters sees a paragraph that begins where every other
-- one does.
local function render_row(entry)
    local prefix = string.format("%-" .. NAME_WIDTH .. "s %-" .. HANDS_WIDTH .. "s %s  ",
        entry.name,
        hands_for(entry),
        glyph_for(entry))

    local room = WIDTH - PARAM_START + 1
    local rendered = render_params(entry.params)

    if #rendered <= room then
        return { prefix .. rendered }
    end

    -- Break between parameters, never inside one. `roster:rost` split across two
    -- lines is not a parameter, it is two pieces of text.
    local lines, line = {}, ""

    for piece in rendered:gmatch("%S+") do
        if line == "" then
            line = piece
        elseif #line + 1 + #piece <= room then
            line = line .. " " .. piece
        else
            table.insert(lines, line)
            line = piece
        end

        if #piece > room then
            io.stderr:write(string.format(
                "019-vocabulary: %s has a single parameter, '%s', that is wider\n"
             .. "  than the %d columns the whole list has room for. Shorten the\n"
             .. "  parameter name -- nothing can wrap one parameter.\n",
                entry.name, piece, room))
            os.exit(1)
        end
    end

    table.insert(lines, line)

    local out = { prefix .. lines[1] }
    for index = 2, #lines do
        table.insert(out, string.rep(" ", PARAM_START - 1) .. lines[index])
    end

    return out
end
-- }}}

-- {{{ header
rule("=")
emit("  NEURON VOCABULARY -- THE CLOSED SET, AS DECLARATIONS")
rule("=")
emit()
emit("A declaration is the whole of what neuron knows about one word. It is")
emit("written once, in the file that implements the operation, and three")
emit("surfaces are drawn from it, none of them written by hand:")
emit()
emit("    the command line    one subcommand, its flags, its usage text")
emit("    the tool schema     one JSON Schema entry handed to a model")
emit("    the catalogue       this table")
emit()
emit("The rule that makes it worth doing: an operation cannot exist as a")
emit("command without existing as a tool. There is no back door where a person")
emit("reaches something a model cannot, and no tool a person cannot first try")
emit("by hand. When the asking half is built, it is handed the same set of")
emit("levers that was already there, and it does not get a private one.")
emit()
emit("Three of the words below are built and have been run against a live")
emit("world: character.teleport, character.return and character.retire. The")
emit("rest are shown at declaration level because that is the level at which a")
emit("vocabulary has to make sense as a whole. Names that sort together, hands")
emit("chosen by one rule, and a parameter that means the same thing everywhere")
emit("it appears are not decisions you can make one operation at a time.")
emit()
-- }}}

-- {{{ legend
rule("-")
emit("  LEGEND")
rule("-")
emit()
emit("hands   how this word reaches the world, in preference order. The first")
emit("        hand that is up is the one used; if none are, it refuses and says")
emit("        which service is down.")
emit()
emit("          cold   a database write. Works while the worldserver is down,")
emit("                 and is the only thing that reaches an offline character.")
emit("          live   a game master command over SOAP. Instant and visible,")
emit("                 and the only thing that reaches an online character")
emit("                 without the server writing over it on its next save.")
emit("          res    a script installed into the running world, which stays")
emit("                 there and keeps deciding after the command has returned.")
emit("          none   neuron answering about itself. No world is touched and")
emit("                 none needs to be running.")
emit()
emit("k       what running it costs.")
emit()
emit("          ?      reads only. No receipt, no apply, safe at any moment.")
emit("          +      changes the world, and a receipt can put it back.")
emit("          !      changes the world, and nothing can put it back.")
emit()
emit("types   the four plain ones arrive as text from a terminal and as parsed")
emit("        JSON from a model, and are the same Lua value by the time any")
emit("        operation sees them. The four named ones do real work in")
emit("        coercion, turning a word a person would say into rows:")
emit()
emit("          str    text                int   whole number")
emit("          bool   true or false       list  several of a thing")
emit()
emit("          rost   a roster: one name, a comma-separated list of names, or")
emit("                 a query such as 'bots hunters 18-20'")
emit("          plac   a place-book name, resolved to a map and four numbers")
emit("          item   a named item list, or a list of item ids")
emit("          rcpt   the id of something already done, from world.receipts")
emit()
emit("          x?     that parameter may be left out")
emit()
-- }}}

-- {{{ table
rule("-")
emit("  THE SET")
rule("-")
emit()
emit(string.format("%-" .. NAME_WIDTH .. "s %-" .. HANDS_WIDTH .. "s %s  %s",
    "name", "hands", "k", "parameters"))
emit(string.rep("-", NAME_WIDTH) .. " " .. string.rep("-", HANDS_WIDTH)
  .. " - " .. string.rep("-", WIDTH - PARAM_START + 1))

local total = 0

for _, section in ipairs(SECTIONS) do
    emit()
    emit(section.title .. "   [" .. section.phase .. "]")
    emit()
    for _, line in ipairs(section.note) do
        emit("  " .. line)
    end
    emit()
    for _, entry in ipairs(section.entries) do
        for _, line in ipairs(render_row(entry)) do emit(line) end
        total = total + 1
    end
end

emit()
emit(string.format("%d words, %d sections.", total, #SECTIONS))
emit()
-- }}}

-- {{{ one declaration in full
rule("-")
emit("  ONE OF THEM IN FULL")
rule("-")
emit()
emit("The table is the shadow. This is the thing casting it -- the declaration")
emit("as it is actually written, today, at the top of src/013-teleport.lua:")
emit()
emit("    Teleport.declaration = {")
emit("        name    = \"character.teleport\",")
emit("        summary = \"Move a roster of characters to a named place.\",")
emit("        hands   = { \"live\", \"cold\" },")
emit("        reversible = true,")
emit("        params  = {")
emit("            { name = \"roster\", type = \"roster\", required = true,")
emit("              describes = \"Who to move: a name, a comma-separated list \"")
emit("                       .. \"of names, or a query like 'bots hunters 18-20'.\" },")
emit("            { name = \"place\", type = \"place\", required = true,")
emit("              describes = \"Where to move them: a named location such \"")
emit("                       .. \"as 'ratchet'.\" },")
emit("        },")
emit("    }")
emit()
emit("The describes field is not documentation. It is the sentence a model")
emit("reads when it is deciding whether this is the word it wants, and it is")
emit("the only thing telling it that a roster may be a query rather than a")
emit("name. A parameter described as \"the roster\" teaches nothing; a parameter")
emit("described with an example of the query language teaches the whole")
emit("feature. Write it for a reader who has never seen this project.")
emit()
-- }}}

-- {{{ the two surfaces
rule("-")
emit("  WHAT IT RENDERS INTO")
rule("-")
emit()
emit("On the command line, one subcommand. The flags are the parameter names,")
emit("the usage line is built from which of them are required, and --plan is")
emit("added by the dispatcher rather than by the operation, because every word")
emit("marked + or ! gets it and none of them should have to ask:")
emit()
emit("    neuron teleport --roster <rost> --place <plac> [--plan]")
emit("      Move a roster of characters to a named place.")
emit()
emit("For a model, one entry in a tool list. Note what happens to the two")
emit("named types: they become plain strings, because a model cannot hold a")
emit("resolved roster and should not try. It says the words a person would say")
emit("and coercion turns them into rows on the way in:")
emit()
emit("    {")
emit("      \"name\": \"character_teleport\",")
emit("      \"description\": \"Move a roster of characters to a named place.\",")
emit("      \"input_schema\": {")
emit("        \"type\": \"object\",")
emit("        \"properties\": {")
emit("          \"roster\": { \"type\": \"string\", \"description\":")
emit("            \"Who to move: a name, a comma-separated list of names, or")
emit("             a query like 'bots hunters 18-20'.\" },")
emit("          \"place\":  { \"type\": \"string\", \"description\":")
emit("            \"Where to move them: a named location such as 'ratchet'.\" }")
emit("        },")
emit("        \"required\": [\"roster\", \"place\"]")
emit("      }")
emit("    }")
emit()
emit("The dot became an underscore. Tool names in the API are restricted to")
emit("letters, digits and underscores, so the registry name and the tool name")
emit("differ by exactly that substitution, applied in one place and reversed")
emit("in one place. It is written down here because a mapping that lives only")
emit("in code is a mapping somebody will reimplement slightly differently.")
emit()
-- }}}

-- {{{ rules across the set
rule("-")
emit("  RULES THAT HOLD ACROSS THE WHOLE SET")
rule("-")
emit()
emit("1.  A name is subject.verb, and the subject is what is being acted on,")
emit("    never the machinery doing it. character.teleport, not teleport, not")
emit("    move.character, not cold.reposition. Sorting the table then sorts by")
emit("    what is being touched, which is how somebody actually looks for a")
emit("    word: they know what they want to change before they know the verb.")
emit()
emit("2.  Hands are a preference, not a requirement. An operation states the")
emit("    order it would like and the dispatcher takes the first that is up.")
emit("    The order is a real decision per operation: teleport prefers live")
emit("    because the change is instant and visible, while relevelling forty")
emit("    offline bots prefers cold, because forty commands over SOAP is forty")
emit("    round trips and one UPDATE is one.")
emit()
emit("3.  Everything marked ! takes a confirm boolean. This is not politeness.")
emit("    The parameter appearing in the schema is what stops a model from")
emit("    reaching an irreversible word in a single step, because it must ask")
emit("    for the confirmation, which means saying out loud what it is about")
emit("    to do while somebody is reading.")
emit()
emit("4.  A parameter name means the same thing everywhere. roster is always")
emit("    who, place is always where, receipt is always which past act. A word")
emit("    that needed roster to mean something else would be the wrong word.")
emit()
emit("5.  Reads have no apply and write no receipt. They declare a single run")
emit("    instead of plan and apply, and --plan on one of them is refused")
emit("    rather than quietly treated as the same thing, because a flag that")
emit("    silently does nothing teaches somebody the wrong lesson about what")
emit("    the flag means on the words where it matters.")
emit()
emit("6.  Optional parameters state their default in the declaration, never")
emit("    inside the function. Both surfaces have to show the default, and a")
emit("    default hidden in a function body can only be shown by someone")
emit("    remembering to copy it, which is a thing that stops happening.")
emit()
emit("7.  Refusals are values and there are exactly four kinds: unknown,")
emit("    argument, unavailable, refused. Small enough that the asking loop can")
emit("    turn any of them into a tool result with useful text, and every one")
emit("    of them names the thing that was wrong.")
emit()
-- }}}

-- {{{ footer
rule("=")
emit("  Generated by src/019-vocabulary.lua, through scripts/vocabulary.")
emit("  Do not edit this file; edit the declarations and run it again.")
emit("  Issue 705 replaces the sketch in that file with the live registry,")
emit("  after which this document describes what exists rather than what is")
emit("  intended, and the difference stops needing to be remembered.")
rule("=")
-- }}}

-- {{{ write
local body = table.concat(lines, "\n") .. "\n"

if output_path then
    local file, why = io.open(output_path, "w")
    if not file then
        io.stderr:write("019-vocabulary: cannot write " .. tostring(output_path)
            .. "\n  " .. tostring(why) .. "\n")
        os.exit(1)
    end
    file:write(body)
    file:close()
    io.stderr:write(string.format("wrote %s -- %d lines, %d words of vocabulary\n",
        output_path, #lines, total))
else
    io.write(body)
end
-- }}}
