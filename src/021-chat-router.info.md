# 021-chat-router.lua

Turns a typed sentence into an operation and its arguments.

**Not a pretend model, and not a rival to one.** It is the substrate a model
will write to. The sibling project's position: *the AI should write the
commands, the player should just ask.* Building the commands first — and making
them speakable by hand — means a model has something real to aim at rather than
an interface invented for it.

## Functions

### `ChatRouter.route(text) -> route | nil`
A route carries `op`, `args`, `changes`, `matched`. **nil means the router has no
opinion** — hand it to a model.

It never guesses. A half-matching sentence is not routed, because a wrong guess
moves characters somebody did not mean to move.

`changes` lives on the route rather than being inferred from the operation name,
so a new phrasing has to state its own blast radius.

### `ChatRouter.vocabulary() -> entries`
What it understands, as `{example, does}` pairs. Two callers need it: the help
command, and the message shown when a sentence was not understood. **The second
is the important one** — an error listing what *would* have worked is the only
thing between a person and guessing.

## What it understands

`where is X` · `who are the X` · `who X` · `move X to Y` · `put X on the Y` ·
`send X to Y` · `undo <receipt>` · `receipts` · `check` · `status` · `help`

## Two details that matter

**Case is preserved.** The patterns match against a lowercased copy but captures
are sliced from the original, so `Grast` and `Aalaan,Aalia` survive intact. A
lowercased character name matches nothing.

**Articles are stripped from rosters only, never places.** "the hunters" is a
roster query with a stray article; "the barrens" is a real place whose article is
part of its name.
