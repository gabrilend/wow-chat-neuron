# 1203 — The Scrapers: Finding Art Out There

## Status
- Phase: 12 (Likeness)
- Blocked by: 1202 (the larder)
- Blocks: 1204 (crossing the wall)
- **This is the issue every stub in phase 12 points at.**

## Current Behavior

**Nothing.** This is the empty half of the phase, and everything else in it is
built as a placeholder standing where this will go.

`creature.reskin` (issue 1201) picks from the 21,381 displays the game already
ships, and declares a stub saying so — on the terminal, in the plan, and in the
end-of-run summary. `scripts/stubs` lists it. Every one of those announcements
names this file.

That is deliberate. The surrounding nine-tenths — asking, planning, confirming,
applying, recording — can all be built and driven before the hardest tenth
exists, and refusing to start until it does is not caution.

## Intended Behavior

Find a model or an icon somewhere on the web and put it in the larder with its
provenance.

```
neuron find --looking-for "goblin" --source open-game-art --plan
```

### One source at a time, each its own thing

Open Game Art first, because it is the friendliest: assets are deliberately
licensed for reuse, tagged, and searchable, and its terms permit automated
access at a civil rate.

**Every source is a separate piece of work.** A scraper is not a general
capability with a site parameter — it is knowledge of one site's markup, one
site's search, one site's licence vocabulary. A "generic scraper" is a thing
that half-works everywhere.

### What it must never do

- **Never store without provenance.** Licence and author come from the same page
  as the file, in the same visit. Separating them loses the licence permanently
  and creates an obligation nobody can discharge. Issue 1202 refuses such an
  asset entry; this must not try to make one.
- **Never take faster than a person would.** One request at a time, with a
  pause, identifying itself honestly. A scraper that hammers a volunteer-run art
  site is a scraper that gets the project blocked and deserves it.
- **Never follow a link off the source.** The blast radius of a crawler is the
  whole web unless somebody draws the line, and the line is: this site, its
  search, its asset pages, its downloads.
- **Never guess a licence.** An asset page with no clear licence is an asset that
  is not taken. Assuming CC0 because it was easy to download is how somebody
  ends up redistributing work they had no right to.

### It only fills the larder

A scraper downloads and records. It does not convert, does not touch the game,
and does not decide what anything is for. Conversion is issue 1204 and is much
harder; keeping them apart means a bad conversion can be redone without going
back to the network, and a scraper can be replaced without touching anything
downstream.

## Suggested Implementation Steps

1. Read Open Game Art's terms and its `robots.txt` before writing a request.
   If automated access is not permitted, the answer is that this issue is not
   built rather than that it is built quietly.
2. Search first, download nothing. Prove the query and the parse against real
   pages while the only thing at risk is being wrong about markup.
3. Add the licence parse. Refuse anything unclear, loudly, with the url.
4. Download one asset, with provenance, into the larder. Stop and look at it.
5. Add the rate limit before the second one, not after.
6. Only then a second source, as a separate module that shares the larder and
   nothing else.

## Open Questions

- **Does Open Game Art permit this?** Unknown, and it is the first question
  rather than a detail. Their terms and `robots.txt` decide whether this issue
  exists.
- **What is being searched for, and in whose words?** "A goblin" is a person's
  word. Site tags are the site's. Something has to bridge them, and a model is
  the obvious bridge and an expensive one.
- **How is a result judged?** A search returns twenty things and nineteen are
  wrong. Choosing needs looking, which is phase 10's cameras pointed at
  something that is not in the world yet.
- **What about icons, which are much easier?** A 64×64 image needs no mesh, no
  rig, no format conversion. Icons may be worth doing entirely first, since they
  cross a much lower wall.

## Related

- Issue 1202 — the larder, which this fills and which refuses undocumented assets
- Issue 1204 — the wall between a downloaded file and something in the game
- Issue 109 — standing stubs, which is how the rest of the phase points here
