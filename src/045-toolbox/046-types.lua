--------------------------------------------------------------------------------
-- 046-types.lua
--
-- What a parameter can be, as an enum. The `types` legend of the vocabulary
-- table, made into something code reads.
--
-- Two fields do the work.
--
-- `json` is what the type becomes in a tool schema. Note that the four resolving
-- types all become "string" -- a model cannot hold a resolved roster and should
-- not try. It says the words a person would say and coercion turns them into
-- rows on the way in. That collapse is the single most important thing in this
-- file, because it is what lets one declaration serve a person typing at a
-- terminal and a model filling in JSON without either of them learning the
-- other's shape.
--
-- `resolves` says whether coercion does real work. A string stays a string; a
-- roster becomes character rows; a place becomes a map and four numbers. Doing
-- that in coercion rather than inside each operation is what stops two
-- operations taking a roster from drifting apart in how they read one.
--
-- Defined here rather than in src/025-enums/ because parameter types are the
-- toolbox's own vocabulary -- they mean something to a declaration and to a
-- schema and to nothing else.
--------------------------------------------------------------------------------

local here = debug.getinfo(1, "S").source:match("^@(.*/)")
local Load = dofile(here .. "../024-load.lua")
local Enum = Load(here .. "../025-enums/026-enum.lua")

return Enum.define("Types", {

    -- {{{ plain -- text from a terminal, parsed JSON from a model, same Lua value
    { "string",  short = "str",  json = "string",  resolves = false,
      accepts = "any text" },

    { "integer", short = "int",  json = "integer", resolves = false,
      accepts = "42 or \"42\"; floored" },

    { "number",  short = "num",  json = "number",  resolves = false,
      accepts = "1.5 or \"1.5\"" },

    { "boolean", short = "bool", json = "boolean", resolves = false,
      accepts = "true, \"true\", \"yes\", 1" },

    { "list",    short = "list", json = "array",   resolves = false,
      accepts = "a JSON array, or a comma-separated string" },
    -- }}}

    -- {{{ resolving -- a word a person would say, turned into rows
    { "roster",  short = "rost", json = "string",  resolves = true,
      accepts = "a character name, a comma-separated list of names, or a "
             .. "query such as 'bots hunters 18-20'",
      becomes = "the character rows it names" },

    { "place",   short = "plac", json = "string",  resolves = true,
      accepts = "a named location from the place book, such as 'ratchet'",
      becomes = "a map and four numbers" },

    { "items",   short = "item", json = "string",  resolves = true,
      accepts = "a named item list, or a comma-separated list of item ids",
      becomes = "the item rows it names" },

    { "receipt", short = "rcpt", json = "string",  resolves = true,
      accepts = "the id of something already done, as shown by 'neuron receipts'",
      becomes = "the receipt itself, read from the log" },
    -- }}}
})
