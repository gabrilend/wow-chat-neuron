# 1204 — Crossing the Wall: A Downloaded File Becomes Something the Game Shows

## Status
- Phase: 12 (Likeness) — the hard one
- Blocked by: 1200 (what a model is), 1202 (the larder), 1203 (the scrapers)
- Blocks: nothing; this is where the phase ends

## Current Behavior

Nothing, and the reason is structural rather than unfinished work.

**The client owns the art.** The server sends a display id; the client looks it
up in `CreatureDisplayInfo.dbc` — which it shipped with in 2010 — and loads
model files out of its own archives. A display id the client does not know
renders as nothing or as a placeholder.

So there is no server-side change, of any kind, that puts new art in front of a
player.

## Intended Behavior

Turn a file in the larder into something a client can display, and get it to
every client.

### Four things, and the fourth is not a technical problem

| | What | Hard because |
|---|---|---|
| 1 | Geometry to **M2** | a 2010 format with a rig, animation sequences, attachment points and bone weights. An OBJ from the web has a mesh and nothing else. |
| 2 | Textures to **BLP** | the format is documented and this is the easy step |
| 3 | New rows in **CreatureDisplayInfo.dbc** and its dependants | DBCs are read at client start, so this means shipping a patched file |
| 4 | **A patch archive every player installs** | not a technical problem |

### The fourth is the phase's real limit

Everything else in this project changes a running world and the players in it
see the change. This does not. It produces a file each person has to put in
their own game directory before anything appears, and until they do they see a
placeholder where everybody else sees a goblin.

That is a **different kind of change** and it should be called one everywhere it
appears. An operation that "adds a model" and silently means "adds a model for
people who already installed the patch you have not made yet" is the worst
failure this project designs against, arrived at from a new direction.

### A rig is the actual difficulty

An M2 is not a mesh. It carries a skeleton, named animation sequences the server
asks for by number, attachment points where weapons go, and per-vertex bone
weights. Open Game Art assets are overwhelmingly static meshes or rigged for
engines that share nothing with this one.

So a converted asset is either **a prop that never animates** — which is fine
for a rock, a crate, a statue, and useless for a goblin — or somebody rigs it,
which is an afternoon of human work per asset and not automatable.

**That split is worth taking seriously rather than designing around.** Props are
achievable. Creatures are not, without a person.

### Icons cross a much lower wall

A spell or item icon is a 64×64 BLP and one DBC row. No mesh, no rig, no
animation. If any part of this phase is worth doing first it is icons, and it is
worth asking whether the phase should be icons only until somebody has rigged
one thing by hand and knows what that costs.

## Suggested Implementation Steps

1. Convert one texture to BLP and display it on something that already exists.
   Smallest possible proof that the pipeline reaches a player's screen at all.
2. Build the patch archive by hand, once, and install it by hand. Learn what
   that actually involves before automating any of it.
3. Only then a static prop: mesh to M2 with no animation, placed as a
   gameobject.
4. Write the "you need the patch" state into every operation that depends on it.
   A player without it must be told, not shown a placeholder.
5. Leave creature rigging alone until steps 1–4 are real. It is the step that
   needs a person, and doing it first means an afternoon of art with no way to
   see it.

## Open Questions

- **Is there an existing OBJ-to-M2 converter?** Model editors for 3.3.5a exist.
  Starting from one is the difference between weeks and never, and nobody has
  looked.
- **How does a player get the patch?** Every distribution answer is a piece of
  infrastructure this project does not have.
- **What does a client without the patch actually render?** Nothing, a question
  mark, or a crash — and which one decides whether missing art is cosmetic or
  fatal.
- **Do DBC edits survive a client update?** For 3.3.5a, nothing updates. That is
  the one thing about this wall that is easier than it looks.
- **Should this be attempted at all?** Reskinning from 21,381 shipped displays
  (issue 1201) covers a great deal of what "change that goblin" means, needs no
  patch, and works today. This issue may be worth writing down and not building.

## Related

- Issue 1200 — the wall, described from the other side
- Issue 1201 — what works without crossing it
