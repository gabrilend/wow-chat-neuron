# 803 — The Split Transcript

## Status
- Phase: 8 (The Voice)
- Blocked by: 802 (the conversation loop), 901 (the browser door)
- Blocks: the context-window work — pruning has nowhere to bite until a
  conversation is made of addressable pieces

## Current Behavior

**Built**, mechanism and all. What is not settled is the POLICY: nothing
prunes automatically, because nobody has decided who does it or when.

Two files per conversation, same stem, `_for_robots.txt` on the machine's half.
Both carry the same header, so either can be opened alone by somebody who has
no idea the other exists. Blocks are routed by a `WHERE` dispatch table, and a
marker with no row in it is an error rather than a guess -- putting an unknown
block in the readable half "just in case" is how the plumbing leaks back into
the thing a person came to read.

Sections are maximal runs, numbered from zero with one counter shared by both
files, and the counter is read off the files rather than kept in memory -- the
transcript is the only state a conversation has, and a counter in a process
would reset on restart and hand out numbers that already exist.

**Reading follows the signposts.** The first version merged by sorting section
numbers, which makes a number a BORDER -- it declares "this section contains
exactly these blocks", and then every question about the format becomes a
question about what a section is allowed to contain. Is one tool call a section?
Is a turn plus its three calls one or three? The format starts having opinions
about the conversation.

A signpost declares nothing about what it separates. It says READ THE OTHER FILE
NEXT, which is a direction and not a boundary. At each intersection exactly one
way is valid and the sign points at it; however much sits on the far side is
however much sits there, and there is no such thing as a wrongly sized section.
The numbers survive as LABELS, so an atom can be named by the edit log, and as a
second opinion: a walk that arrives out of numbered order says so rather than
reordering anything.

That also answers what an atom is. An atom is whatever lies between two signs. `Transcript.blocks(handle, id)` gives the whole
conversation; with `"human"` or `"robots"` it gives one half.
`Transcript.stitched` renders the merge back as the one text the format used to
be, which is what the live chat window draws itself from.  `Transcript.said`
is the human half filtered to `you` and `neuron`, which is what the menu's
prior-conversation viewer asks for with `?said=1`.

**The edit log** is a third file, `_edits.txt`, append-only, holding `drop N`,
`keep N` and `fold N M  what it says instead`, each under a comment carrying the
when and the why. Every read replays it from the start over the atom list, so
the current state is derived rather than stored, and `keep` is how an edit is
undone. The alternative -- rewriting the section list in place -- is cheaper and
destroys the record of what was cut and why. Same reason `append` never
rewrites: a log that can be edited is a record you cannot trust.

Only `Transcript.messages` replays it, because that is the only reader whose
output is spent. What a person sees costs nothing and is never pruned.

`scripts/neuron atoms <id>` lists them with their sizes and states, and
`--drop` / `--keep` / `--fold ... --says` write log lines. Thirty-two tests.

Old single-file conversations still open, and `Transcript.summary` reports
`old_format` so the compatibility path is visible rather than silent.

Fifty-seven tests, covering the seam: that either half stands alone, that
merging restores the original order, that a section really is a run, and that a
pre-split conversation still reads.

Three bugs fell out of the work.

`is_pointer(marker) and nil or {...}` always yields the table -- `and nil` is
falsy, so `or` takes the right-hand side. Every pointer sailed through as a
block with no text, and the conversation came back with three extra empty turns
in it.

Tool arguments were parsed with `([%w_]+)=([^\n]*)`, which takes everything to
the end of the line as the first value. A call written `type=undead  level=12`
came back with `type` set to `"undead  level=12"` and no `level` at all. It had
been wrong since multi-argument calls existed; it looked right in the file.

The opening turn made the first message an assistant turn, which the Anthropic
API refuses outright -- a conversation must begin with a person. Ollama
tolerates it, so it was invisible on the bench and would have failed on the
first real request. `Transcript.messages` now hands the opening back separately
and the loop appends it to the instructions, so the model still sees every word
of it.

## Intended Behavior

### Two files, one stream

A conversation becomes two files with the same stem:

    2026-09-06/001530-a3f1.txt              what people said
    2026-09-06/001530-a3f1_for_robots.txt   what the machinery said

The split is by AUDIENCE, not by importance:

| block      | file   | why |
|------------|--------|-----|
| `[system]` | robots | instructions to a model, not conversation |
| `[you]`    | human  | somebody said it |
| `[neuron]` | human  | the model said it |
| `[tool]`   | human  | ONE LINE: which word, with its arguments |
| `[result]` | robots | the bulky half, and nobody reads it for pleasure |

A tool call stays on the human side because "it looked up undead creatures
around level 12" is part of the story. Its ANSWER does not: that is eighty
lines of table and it belongs with the plumbing.

### Sections, numbered, shared between the files

Blocks are grouped into **sections**: a maximal run of consecutive blocks
belonging to the same file. Sections are numbered from zero with ONE counter
shared by both files, so section 4 is section 4 whichever file it landed in.

Each file writes a marker where the other file's section belongs:

    ...in the human file...
    [tool] world_creatures
    type=undead  level=12

    [from_robots] 7

    [neuron]
    There are four kinds worth using at that level.

    ...in the robots file...
    [from_conversation] 6

    [result] 7
    entry  name                 level  rank
    ...

Stitching is then merging by number, and the markers are signposts rather than
the mechanism. That ordering matters: if one file is missing or truncated, the
other still yields a correctly ordered partial conversation instead of a
plausible wrong one.

### Who reads which

- **The chat window, live** — both, stitched. Unchanged behaviour.
- **The prior-conversation viewer on the menu** — the human file only, and
  filtered further to `[you]` and `[neuron]`. No system prompt, no results,
  no tool lines.
- **Reviving a conversation** — both, stitched, in section order. The model
  must see exactly what it saw before.
- **The conversation list** — the human file, for the opening line and the
  counts.

### Atoms

A section is an **atom**: the smallest thing that can be included or left out
of what gets sent to a model. Numbering them is the whole point of this issue;
using the numbers is the next one.

The shape that follows, sketched here so the numbering is built for it rather
than retrofitted:

A third file, `<stem>_edits.txt`, append-only, holding one line per operation:

    keep 0
    drop 12
    fold 13 14 15 -> "asked about undead creatures three times"

Rebuilding the context replays that log from the start over the section list.
Append-only because a conversation is a thing that happened; an edit log that
can be edited is a record that cannot be trusted, which is the same reason
`Transcript.append` never rewrites.

This is NOT built by this issue. See the open questions.

## Suggested Implementation Steps

1. `Transcript.path(handle, id, which)` — `which` is `"human"` (default) or
   `"robots"`. One function so the naming rule lives in one place.
2. `Transcript.begin` writes the header to both, and the system prompt to the
   robots file as section 0.
3. `Transcript.append` decides the file from the marker, via a dispatch table
   rather than a chain of comparisons. It writes a `[from_*]` marker whenever
   the file changes from the previous block, and stamps each section number.
4. `Transcript.blocks` reads both, merges by section number, and returns what
   it always returned so nothing downstream changes.
5. `Transcript.blocks(handle, id, "human")` returns one file's blocks, for the
   viewer and the list.
6. `Transcript.read` gains the same argument.
7. The menu's prior-conversation viewer asks for the human half and filters to
   `[you]` and `[neuron]`.
8. Old single-file conversations still read. A transcript with no robots file
   beside it is a transcript from before the split, and it is read whole. The
   list marks it, because a silent compatibility path is a fallback and a
   fallback is a warning.

## Related

- `src/067-transcript.lua` — the format and every reader of it
- `src/068-conversations.lua` — opens, appends, revives
- `src/059-menu.lua` — `Menu.conversation`, the prior-conversation viewer
- `assets/chat.html` — renders blocks for a live window
- `issues/1008-the-chatlog-and-relevance-decay.md` — the other half of the
  context-budget problem, from the world side rather than the file side

## Open Questions

1. ~~Does an edit log replay, or is the section list rewritten in place?~~
   **Settled: replay.** Append-only, walked from the start on every read.

2. ~~What is an atom when a turn has several tool calls?~~
   **Settled: the question does not arise.** Markers are signposts, not
   borders -- they direct traffic rather than declare extents, so an atom is
   whatever lies between two signs and the format holds no opinion about it.

3. ~~Who decides what to prune, and when?~~
   **Settled, and it is two separate things.**

   *Deleting a transcript* is the user's, only. Nothing automatic touches the
   files, and `scripts/neuron atoms` is the hand-driven way in.

   *A model shortening its own memory* is `memory.forget`, an `internal` lever
   in both vocabularies. It runs immediately -- there is nothing to agree to,
   and a model summarising itself mid-sentence cannot stop and wait. One atom
   per call, deliberately: a model that can drop five will drop five and the
   fifth will be something it needed.

   It points by QUOTATION rather than by number, because a model handed atom
   numbers would keep a mental index of a list it cannot see and get it wrong
   in the ordinary way. `src/069-similarity.lua` turns a paraphrase into one
   atom by character-trigram containment -- positionless, so inserting junk in
   the middle displaces nothing -- or into a refusal naming the ambiguity.

   The call and its answer go into the transcript and are left OUT of what is
   replayed. Otherwise the lever would be absurd: every deletion would add a
   tool call and a result, so shortening the conversation would make it longer.

   OPEN, still: **an atom only exists where the stream crosses between the two
   files**, which is where tool calls are. A conversation of pure back-and-forth
   with no tool calls has exactly two atoms -- the instructions and everything
   else -- and nothing to prune but the whole thing. That is defensible, since
   tool results are the bulk of what makes a conversation long, and it is not
   obviously right.
   On every revive, by budget? Only when a send is refused for length? By a
   model asked to summarise its own history? Each implies a different place for
   the code.

4. **Should a dropped atom leave a visible scar?**
   A fold does -- it puts one line where several blocks were, because a model
   told something is missing behaves better than one handed a gap it cannot
   see. A DROP does not, and that asymmetry was a decision made while building
   rather than one anybody agreed to.

8. **What happens when a drop orphans a tool result?**
   Dropping the human atom holding a call while keeping the machine atom
   holding its answer leaves a `tool_result` with no `tool_use`.
   `Transcript.messages` currently ignores a stranded result rather than
   emitting it, so nothing breaks -- but nothing warns either, and the model
   silently loses an answer it can see the question for.

5. **Is the recorded system prompt a record or the source?**
   `Transcript.begin` writes the instructions into the robots half, and the
   comment above it says a revived conversation is governed by the prompt it
   was begun under. It is not: `Loop.ask` calls `Loop.system_prompt` freshly
   every turn, so the recorded one is a record of what WAS said and the live
   one is whatever the code says today. Two answers, and the comment claims the
   one that is not happening. Which should it be?

6. **Where does the opening turn really belong?**
   It is now lifted out of the messages and appended to the instructions. That
   keeps the API happy and the model still reads it -- but it has moved from
   "something neuron said" to "context neuron was given", and those are not the
   same thing to a model deciding whether it has already greeted somebody.

7. **Do the two files need to be written atomically together?**
   A crash between the two appends leaves a section number in one file with no
   partner. Harmless for reading -- the merge just has a gap -- but it means
   section numbers cannot be assumed contiguous, and anything that assumes it
   later will be wrong on exactly the conversations that mattered.
