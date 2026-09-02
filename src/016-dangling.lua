--------------------------------------------------------------------------------
-- 016-dangling.lua
--
-- Find rows that refer to a character who does not exist.
--
-- This is the proof that a removal was complete, and the alarm that says a
-- future one was not. The live deployment held nine hundred characters whose
-- accounts had been deleted; the same shape of mistake one level down leaves
-- inventory rows, spell rows, and item rows pointing at nobody, and nothing
-- anywhere complains.
--
-- Nothing here writes. It counts, and it is safe to run at any time.
--
-- The table list is the same one 015-retire.lua deletes from, read from that
-- module rather than copied, so a table added to the removal is automatically
-- checked and the two cannot drift apart.
--------------------------------------------------------------------------------

local Dangling = {}

-- {{{ sibling(neuron_root, filename)
local function sibling(neuron_root, filename)
    return dofile(neuron_root .. "/src/" .. filename)
end
-- }}}

-- {{{ NOT_CHARACTER_KEYED
-- Statements whose key column does not name a character whose absence is a
-- problem, and which therefore must not be checked this way.
--
-- `mail.receiver` and `character_social.friend` DO name characters, and a
-- dangling one there is a real finding. But `item_instance.owner_guid` is zero
-- for items that are legitimately unowned -- sitting in a mail attachment or a
-- guild bank -- so a plain "no matching character" test would report every one
-- of those as dangling and drown the real findings.
local ZERO_MEANS_UNOWNED = {
    ["item_instance.owner_guid"] = true,
}
-- }}}

-- {{{ Dangling.check(handle)
-- Count dangling rows for every table the removal touches.
--
-- One query, built as a UNION, rather than one per table. Forty round trips to
-- answer "is anything left over" is slow enough that nobody would run it, and a
-- check nobody runs is not a check.
function Dangling.check(handle)
    local ColdHand = sibling(handle.neuron_root, "002-cold-hand.lua")
    local Retire   = sibling(handle.neuron_root, "015-retire.lua")

    local parts = {}
    local seen = {}

    for _, deletion in ipairs(Retire.DELETIONS) do
        local signature = deletion.table .. "." .. deletion.key
        -- character_social appears twice, on two different keys; both are
        -- checked, but a table/key pair is only checked once.
        if not seen[signature] then
            seen[signature] = true

            local extra = ""
            if ZERO_MEANS_UNOWNED[signature] then
                extra = " AND x.`" .. deletion.key .. "` <> 0"
            end

            table.insert(parts, string.format(
                "SELECT '%s' AS tbl, '%s' AS keycol, COUNT(*) AS leftover "
             .. "FROM `%s` x LEFT JOIN characters c ON c.guid = x.`%s` "
             .. "WHERE c.guid IS NULL%s",
                deletion.table, deletion.key, deletion.table, deletion.key, extra))
        end
    end

    local rows, why = ColdHand.read(handle, handle.db_characters,
        table.concat(parts, " UNION ALL "))

    if not rows then
        return nil, why
    end

    local findings, total = {}, 0
    for _, row in ipairs(rows) do
        local leftover = tonumber(row.leftover) or 0
        if leftover > 0 then
            table.insert(findings, {
                table = row.tbl, key = row.keycol, leftover = leftover,
            })
            total = total + leftover
        end
    end

    table.sort(findings, function(a, b) return a.leftover > b.leftover end)

    return { findings = findings, total = total, checked = #parts }
end
-- }}}

-- {{{ Dangling.describe(result)
function Dangling.describe(result)
    local lines = {}

    if result.total == 0 then
        table.insert(lines, string.format(
            "no dangling rows. %d table/column pairs checked; every row that "
         .. "names a character names one that exists.", result.checked))
        return table.concat(lines, "\n")
    end

    table.insert(lines, string.format(
        "%d dangling row%s across %d table%s -- rows naming characters that do "
     .. "not exist:", result.total, result.total == 1 and "" or "s",
        #result.findings, #result.findings == 1 and "" or "s"))
    table.insert(lines, "")

    for _, finding in ipairs(result.findings) do
        table.insert(lines, string.format("  %-36s %-12s %9d",
            finding.table, finding.key, finding.leftover))
    end

    table.insert(lines, "")
    table.insert(lines, "These are residue: something removed characters without "
        .. "removing what referred")
    table.insert(lines, "to them. Nothing will complain about them and nothing "
        .. "will clean them up.")

    return table.concat(lines, "\n")
end
-- }}}

return Dangling
