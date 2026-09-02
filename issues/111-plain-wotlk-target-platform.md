# 111 — The Plain WotLK Target Platform

## Status
- Phase: 1 (Reach)
- Blocked by: nothing in neuron. The work is in the DEPLOYMENT, not here.

## Current Behavior

neuron points at wow-chat-2026's `vanilla` profile, which is described as
"default WotLK + playerbots" and is not that any more. It has accumulated a
substantial ruleset: level cap 40, characters starting at level 20, per-race
starting zones, class-specific starter kits, pretrained abilities, mount level
gates, grounded flightmasters, starting professions, Death Knights disabled,
and a custom spell layer.

That is a designed game. It is a fine thing to be, and it is not a neutral
platform to open a chat window onto.

## Intended Behavior

A profile that is **stock WotLK 3.3.5a + mod-playerbots + mod-ale, and nothing
else**. This is the platform the neuron chat window targets: a world where
everything behaves the way the whole audience already expects, so that anything
strange in it was put there deliberately by someone asking for it.

This matters for the same reason the license document does. The value of an old,
widely-known version of the game is that nobody has to learn it. A profile that
quietly changes the level cap and the starting level has spent that value
without buying anything with it.

### What the archaeology found

The user's expectation was that this state exists in history and can be
recovered from the git record. It does not, quite:

| Commit | Date | What it did |
|--------|------|-------------|
| `1953e5e` | 2026-06-03 | Created the vanilla profile — WotLK + playerbots, **no ALE** |
| `b55a774` | 2026-06-04 | Split the Lua corpus per profile — **ALE arrives** for vanilla |
| `6ee263b` | 2026-06-04 | Wired the whole 148 ruleset through the config patches |

ALE and the ruleset landed on the same day. "Vanilla with ALE, before the
ruleset" was a window of hours at most, and there is no commit that cleanly is
it. Checking one out is not the route.

### The route is subtraction, and it is exact

The deployment gates every configuration patch on a profile list, which makes
the ruleset enumerable rather than a matter of judgment. Seven patches are
`"vanilla"`-only and constitute the entire config-side ruleset:

| Patch | Removes |
|-------|---------|
| `C006c-max-level-40` | the level cap of 40 — stock WotLK is 80 |
| `C007c-starting-level-20` | characters starting at 20 — stock is 1 |
| `C014-vanilla-playerbot-level-cap` | the bot level band |
| `C015-vanilla-disable-deathknight` | the DK ban — stock WotLK has them |
| `C018-vanilla-playerbot-account-count` | bot account sizing |
| `C020-vanilla-playerbot-population` | bot population sizing |
| `C022-vanilla-custom-spells` | the custom spell layer |

Everything else applying to vanilla is gated `"all"` or shared with other
profiles — database connections, directory paths, network ports, realmlist,
realm id, GM login state, missing config keys. All of those are infrastructure
and all of them stay.

Alongside those, three more things come out:

- The seven SQL files in `sql/vanilla/db_world/` — starting zones, starting
  equipment, flight-path removal, ability pretraining, mount requirements, kit
  level cap, professions.
- `sql/vanilla/db_characters/01-no-intro-cinematic.sql` — arguably a courtesy
  rather than a ruleset; a judgment call, and the reason it is listed here
  rather than assumed.
- `src/lua-vanilla/auto-equip-starter-kit.lua` — the 148k starter-kit hook.

What remains is mod-playerbots, mod-ale, the compile-fix patches the fork needs
to build at all, and the infrastructure. Which is the ask, exactly.

### Where this work happens

**Not in neuron.** Adding a profile means touching the deployment's config
patches, SQL corpus, and profile scripts, and neuron's whole position is that
it does not build, patch, or install servers.

So this issue is a **requirement on the target**, and its implementation is a
ticket in wow-chat-2026's own tracker. What neuron does about it is one line in
`config/deployment.lua` once the profile exists, plus a validator that checks
the profile it is pointed at is the plain one and warns when it is not.

This is the first real test of the control-plane boundary, and it is worth
noticing that the boundary held: the answer to "neuron needs a different server"
is "then the server project builds one", not "neuron grows a build system".

## Suggested Implementation Steps

1. Decide the profile's name. `plain` says what it is. `basic` was considered in
   the deployment's own issue 152 for a different purpose and may collide.
2. In the **deployment**: add the profile to its profile list, gate the seven
   C-patches to exclude it, and give it an empty SQL corpus and an empty Lua
   corpus.
3. In the **deployment**: build and install it, and confirm a fresh character
   starts at level 1 with an 80 cap and no kit.
4. In **neuron**: point `config/deployment.lua` at it.
5. In **neuron**: write the platform validator — read the deployment's active
   profile and its applied-patch manifest, and report anything that would make
   the world behave unexpectedly. Warn, do not block; someone may be pointing at
   a designed profile on purpose.

## Open Questions

- **Does the intro cinematic removal stay?** It is not a rule change, it is a
  convenience, and it saves everyone forty seconds. Removing it is the purist
  answer and keeping it is the kind one.
- **Do Death Knights come back?** Stock WotLK has them, so yes by the stated
  definition. They start at 55 and are much stronger than a level 1 character,
  which is also stock WotLK and also going to be surprising.
- **Should neuron refuse to run against a non-plain profile?** Currently
  planned as a warning. A refusal would be safer and would make the tool
  useless against the deployment that actually exists today.

## Related

- `../wow-chat-2026/issues/148-vanilla-profile-default-wotlk-playerbots.md` —
  the profile this subtracts from, and its own account of why it drifted
- `docs/architecture.md` — open question 1, the control-plane boundary
- `LICENSE.md` — why a widely-known ruleset is the valuable thing
