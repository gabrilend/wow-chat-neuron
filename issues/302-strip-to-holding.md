# 302 — `character.strip`: Take What They Have and Hold It

## Status
- Phase: 3 (Outfitting)
- Blocked by: 105 (reading the world), 202 (rosters)

## Current Behavior

Nothing exists. wow-chat-2026's first-login hook strips a character by calling
RemoveItem on every slot, which **destroys** the items. That is correct for a
character being created, who owned nothing anyone wanted.

It is not correct here. Stripping a character who has been played is throwing
away somebody's things.

## Intended Behavior

> equip overwrites what they have, strip takes what they have and removes it to
> a list somewhere.

Strip empties a character and **puts what it took into a holding list**, keyed to
that character and that moment. Nothing is destroyed.

The list can then be given back, given to somebody else, or left where it is.

### Where the holding list lives

A real table, `neuron_holding`, in the characters database. Not a temporary
table and not a MEMORY table, and the reason is worth stating because the
question was asked directly:

MySQL offers two kinds of ephemeral storage, and they expire differently:

| Kind | Lives as long as | Loses |
|------|------------------|-------|
| `CREATE TEMPORARY TABLE` | one connection | everything, when that connection closes |
| `ENGINE=MEMORY` | the server process | every row, when mysqld restarts |

A MEMORY table is exactly "a little table that is removed when the server
restarts", and it is the right tool for genuinely scratch work — the character
removal in issue 404 uses one to hold a guid list for the length of a single
transaction.

It is the **wrong** tool for held gear. Somebody's equipment disappearing because
the database process bounced is a bug that looks like theft, and MEMORY tables
also cannot hold `TEXT` or `BLOB` columns, which item rows have. So held gear
goes in an ordinary InnoDB table and stays there until somebody moves it.

The distinction is the useful part: **ephemeral for things nobody would miss,
durable for things somebody would.**

### What is actually held

Not a copy of the items — a **reference**. The `item_instance` rows already exist
and already carry each item's enchantments, durability, and stack size. Copying
them would create a second truth about the same sword.

So a holding row records: which character it came from, which `item_instance`
guid it is, which slot it was in, and when. The item itself is simply no longer
referenced by `character_inventory`, and is referenced by the holding table
instead. Giving it back is moving the reference, not recreating the item.

This is what makes strip and give-back exactly inverse, and it is why the
holding list is not a temporary table: an `item_instance` row with nothing
pointing at it is precisely the dangling residue `neuron check` exists to find.

## Suggested Implementation Steps

1. Write the `neuron_holding` table: holding id, character guid, item guid, the
   slot it came from, the bag it came from, a timestamp, and a label.
2. Write the read that lists a character's current inventory as slot/item pairs,
   over `character_inventory` joined to `item_instance` and `item_template`.
3. Write the strip: for each item, insert a holding row and remove the
   `character_inventory` row, in one transaction. The item row is untouched.
4. Write the give-back: the inverse, into the same or a different character.
5. Extend `neuron check` to notice `item_instance` rows referenced by neither
   `character_inventory` nor `neuron_holding` — an item pointed at by nothing is
   the residue this design exists to avoid creating.
6. Test the round trip on a character with a full inventory, including a stack
   and an enchanted weapon, and confirm the enchantment survives — which it must,
   because the item row was never touched.

## Open Questions

- **How long does a holding list live?** Forever is simple and accumulates.
  Expiring it destroys things. Probably it lives until somebody empties it, and
  `neuron check` reports how much is being held.
- **Can two characters be given the same held item?** No, and the table's
  uniqueness on item guid should make that impossible rather than merely
  discouraged.
- **What about equipped items versus bagged ones?** The slot is recorded either
  way, so a give-back can restore the exact layout. Whether it should, or should
  just hand things over in a bag, is a gameplay question.

## Related

- Issue 303 — equip, the other half
- Issue 404 — the character removal, which uses the *other* kind of ephemeral
  table and explains why the distinction matters
