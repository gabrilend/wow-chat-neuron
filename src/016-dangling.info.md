# 016-dangling.lua

Find rows that name a character who does not exist. Reads only; safe at any time.

## Functions

### `Dangling.check(handle) -> result | nil, why`
Returns `findings` (table, key, leftover), `total`, and `checked` — how many
table/column pairs were examined.

One query built as a UNION rather than one per table. Forty round trips to answer
"is anything left over" is slow enough that nobody would run it, and a check
nobody runs is not a check.

### `Dangling.describe(result) -> string`

## Where the table list comes from

`Retire.DELETIONS` — **read from that module, not copied**. A table added to the
removal is automatically checked, and the removal and its verification cannot
drift apart.

## One exception, and why

`item_instance.owner_guid` is legitimately zero for items nobody owns — sitting
in a mail attachment or a guild bank. A plain "no matching character" test would
report every one of those and drown the real findings, so zero is excluded there.

That exception is why the check is a module rather than a query: the shape is
almost uniform, and the almost is the part that matters.

## It exits non-zero when it finds anything

Residue is a finding, not a statistic. Per the standing position that a warning
is an error, the command fails so anything running it in a build or a hook
notices.
