# 303 — `character.equip`: Overwrite With an Item List

## Status
- Phase: 3 (Outfitting)
- Blocked by: 301 (item lists), 302 (strip to holding)

## Current Behavior

Nothing exists.

## Intended Behavior

> equip overwrites what they have

Give a roster an item list. Whatever occupied those slots is replaced.

Replaced, not destroyed — anything displaced goes to the holding list from
issue 302, by the same mechanism strip uses. So equipping is strip-then-fill for
the slots the list touches, and leaves alone the slots it does not.

That makes the two operations compose without either needing to know about the
other:

| What you run | What happens |
|--------------|--------------|
| `equip` with a full kit | Everything replaced; the old kit is held |
| `equip` with one item | That slot replaced; the rest untouched |
| `strip` then `equip` | The 2026 first-login behaviour, with nothing destroyed |
| `strip` alone | Character emptied, everything held |

### Slot routing comes from the item, not from the caller

An item list names entries, not slots. Which slot each goes to is read from
`item_template.InventoryType`, exactly as the sibling project's first-login hook
does — that mapping is a fact about the item and duplicating it in a caller is
how a list ends up putting a helm on a foot.

Two cases the routing table alone does not cover, both learned from the sibling
project rather than rediscovered:

- **One-handed weapons** can go to either hand, so the second copy of a
  one-hander routes to the off hand when the main hand is taken.
- **Containers must be equipped before anything that goes inside them**, and
  ammunition must be added *after* its quiver exists, or the engine puts the
  arrows in the backpack. The install order is therefore bags, then quiver, then
  everything else, then ammunition — not alphabetical, not list order.

### Proficiency is part of equipping

A weapon a class has never trained cannot be equipped at all — the engine gates
it on a proficiency spell, not on data. The sibling project learned this the
expensive way: kit weapons silently failed to equip until proficiencies were
learned first.

So equipping a weapon means learning its proficiency first, and that is part of
this operation rather than a thing the caller remembers.

## Suggested Implementation Steps

1. Write the item-list store and resolver (issue 301).
2. Write the slot routing from `item_template.InventoryType`, with the
   one-handed dual-wield case.
3. Write the displacement: anything in a slot the list will fill goes to holding
   first, by the same path as strip.
4. Write the install ordering: containers, quiver, equipment, ammunition.
5. Write the proficiency step, before any weapon is installed.
6. Test the composition: equip one item and confirm the other slots are
   untouched; strip then equip and confirm the character ends up in exactly the
   list and nothing else.

## Open Questions

- **Does equip work through the live hand at all?** For an online character, the
  game master command surface has `additem`, which adds rather than equips, and
  equipping is done by the player. So an online character may only be equippable
  by asking them to do it, or by logging them out first. This needs checking
  against a running server and may be a real limit on the operation.
- **What happens when an item cannot be equipped by that class or level?** Held
  rather than forced, and reported. Forcing produces a character wearing
  something the client will not display.

## Related

- Issue 302 — strip, and where displaced things go
- `../wow-chat-2026/src/lua-vanilla/auto-equip-starter-kit.lua` — the install
  ordering and proficiency lessons, learned there first
