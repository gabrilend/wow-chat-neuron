# 019-vocabulary.lua

The closed set of words neuron knows, held as declarations, and the renderer
that prints them as `docs/vocabulary.txt` at eighty columns.

Two halves that do not know about each other. The data half is a list of
operations in the same shape the live declarations use in `013-teleport.lua`,
`014-return.lua` and `015-retire.lua`. The render half turns any list of that
shape into the document. Swapping the first for the real registry does not
touch the second — which is the whole test of whether the sketch was honest.

## Run it

`scripts/vocabulary` rewrites `docs/vocabulary.txt`. `--stdout` prints instead;
`--out <path>` writes elsewhere. Nothing else in the project reads it.

## The declaration shape

| Field | Type | Meaning |
|-------|------|---------|
| `name` | string | `subject.verb` — what the operation is called on every surface |
| `hands` | array of string | `cold`, `live`, `res`, `none`, in preference order |
| `kind` | string | `read`, `change`, or `final` |
| `params` | array | ordered; each is `{name, type, "?" when optional}` |

`kind` renders to one character — `?`, `+`, `!` — because three states is the
whole truth about what a word costs: it reads, it can be put back, it cannot.

The live declarations carry two fields this sketch does not: `summary` and a
`describes` string per parameter. Both are prose that would not fit an
eighty-column row, and both matter more than anything here — `describes` is
what a model reads when deciding whether this is the word it wants.

## What it refuses

A rendered line past eighty columns stops the run and writes nothing. Two
messages, because the two causes have different fixes: a prose line that ran
long is a wrapping mistake, and a parameter list that ran long means the
operation takes too many arguments to be one word.

## Why forty-two words when three exist

Names that sort together, hands chosen by one rule, and a parameter meaning the
same thing in every operation are not decisions that can be made one operation
at a time. The set had to be laid out whole before the registry that enforces
it gets built.

Issue 701 builds the registry. Issue 705 points this renderer at it and deletes
the sketch.
