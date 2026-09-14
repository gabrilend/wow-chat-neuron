# 1202 — The Larder: Keeping What Was Found

## Status
- Phase: 12 (Likeness)
- Blocked by: nothing
- Blocks: 1203 (the scrapers), 1204 (crossing the wall)

## Current Behavior

Nothing outside the deployment has ever been kept. Neuron reaches out twice — to
a MySQL socket and to a model's API — and retains nothing from either.

## Intended Behavior

A local store of assets that came from somewhere else, with **where each came
from written down beside it**.

```
assets/larder/
  <hash>/
    original.zip          exactly what was downloaded, untouched
    provenance.txt        where, when, who made it, under what licence
    converted/            whatever it was turned into
```

### Provenance is the whole point, not bookkeeping

Open Game Art is not one licence. It is CC0, CC-BY, CC-BY-SA, GPL and OGA-BY,
per asset, chosen by whoever uploaded it. CC-BY means **attribution is required
wherever the work appears** — and a game server showing a model to players is
somewhere it appears.

An asset whose licence was not recorded at download time is an asset that can
never be safely used, because the obligation is unknowable afterwards. The
download is one HTTP request and the licence is on the same page; separating
them by even an hour loses it.

So: **an asset with no provenance file is not in the larder.** Not a warning —
it simply is not stored, because storing it creates an obligation nobody can
discharge.

### Content-addressed, and the original kept untouched

The directory name is a hash of the original bytes. Two routes to the same file
are one entry, and a file that changed upstream is a new one rather than a
silent replacement.

The original is never modified. Conversion writes beside it, so a conversion
that turns out wrong can be redone from the source without going back to the
network — and so the thing whose licence was recorded is still the thing on
disk.

### Not in the RAM tier, and not in git

Downloads are large, durable, and not this project's work. They belong on disk
and out of version control, with the provenance files being the only part worth
tracking — they are small, they are text, and they are the record that matters.

## Suggested Implementation Steps

1. Write the larder before any scraper. A scraper with nowhere to put things
   writes them somewhere temporary and the provenance is lost in the first hour.
2. Refuse to store without a provenance file. Every field required; none guessed.
3. Hash the original bytes for the directory name.
4. `world.larder` as a read, so what is held can be listed and audited.
5. A licence summary that says what obligations the current contents carry, in
   one place. Somebody will eventually need to answer "what do we owe and to
   whom" and answering it by reading directories is answering it wrong.

## Open Questions

- **What must a provenance record contain?** Source url, retrieval date, author
  as they wrote it, licence identifier, and the licence text itself — because a
  url to a licence is a url that can go away.
- **Does attribution reach the player?** CC-BY says wherever it appears. In a
  game that might mean a credits panel nobody built, and neither the game nor
  this project has anywhere to put one.
- **What happens when an asset is withdrawn upstream?** The licence granted does
  not expire, and the copy is the evidence of what it was.
- **Is the larder per-deployment or per-machine?** Shared saves space and blurs
  which world owes which attribution.

## Related

- Issue 1203 — what fills it
- Issue 1204 — what reads it
