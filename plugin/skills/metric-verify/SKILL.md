---
name: chord-metric-verify
description: Verify that a revenue, order-count, or LTV figure from the Chord warehouse is using the correct basis before it leaves the room — checking revenue basis (gross vs. net), order status filter, and UTC/local-timezone alignment with Shopify admin. Use when the user says 'double-check this', 'why doesn't this match Shopify?', 'verify this number', or is about to share a figure with leadership. Also use proactively after any chord-analyst query that touches orders.total or lifetime_value.
---

# Chord Metric Verify — pre-flight number check

You have access to `mcp__chord__*` tools exposed by the chord MCP server.

This skill is a verification pass, not a data-retrieval pass. Run it _after_ a
number has been produced (by `ask`, by `execute_sql`, or by the user pasting a
figure) and _before_ the user acts on it. The goal is to catch the three traps
that produce plausible-but-wrong results.

Use the Analyst-tier tools for this workflow. Do not call `ask`.

## The three traps

### Trap 1 — Revenue basis (gross vs. net)

`orders.total` and `dim_customers.lifetime_value` are **gross** figures.
Partial refunds are NOT deducted — the order status stays `completed` and
`orders.total` is not adjusted. The only net-revenue column is
`fct_orders.net_total` (= `total - refund_amount`), computed by dbt.

**Default assumption to surface:** If the user asked for "revenue" with no
qualifier, the answer used gross totals. Say so explicitly. If they asked for
"net revenue" or "after refunds," the SQL must use `fct_orders.net_total`.

### Trap 2 — Order status filter

Valid statuses: `pending`, `completed`, `cancelled`, `refunded`.
Revenue queries must filter `status = 'completed'`. Cancelled orders never had
payment captured; refunded orders had payment reversed. Both must be excluded
from any financial metric unless the user explicitly asks to include them.

**Check:** Does the SQL (or the pipeline query) have `WHERE status = 'completed'`?
If not, flag it.

### Trap 3 — UTC vs. Shopify admin timezone

All timestamps in the warehouse are **UTC**. Shopify admin displays dates in
the store's configured local timezone (often PST/PDT for US brands).

A query for "last month's revenue" uses UTC date boundaries. Shopify admin's
"last month" uses the store's local timezone. For a PST store, the gap is 8
hours at each boundary — roughly a day of orders at each end of the month
that fall in different calendar months depending on which surface you're using.

**When to surface this:** Any time the user mentions comparing a Copilot or
SQL result to a Shopify admin figure, or says "the numbers don't match."

Fix to offer:
```sql
WHERE DATE_TRUNC('month', CONVERT_TIMEZONE('UTC', 'America/Los_Angeles', order_date))
    = DATE_TRUNC('month', CONVERT_TIMEZONE('UTC', 'America/Los_Angeles', CURRENT_DATE()))
```

## Tools

- **`search_instructions`** — retrieve the active project conventions for
  revenue basis, order filters, and any tenant-specific overrides. Always run
  this first — a tenant may have stored custom rules that override the defaults
  above.

- **`search_saved_views`** — check whether a canonical saved view covers this
  metric. If it does, compare the SQL being verified against the view's SQL. A
  divergence (e.g. wrong status filter, different date column) is a finding.

- **`execute_sql`** — run a cross-check query if needed. For example: if the
  user suspects a timezone gap, run the same aggregation with and without
  `CONVERT_TIMEZONE` to quantify the difference.

## Workflow

1. **`search_instructions`** — load the tenant's conventions. Note any that
   directly affect the metric being verified (revenue basis, test-order
   exclusion, date anchoring).

2. **`search_saved_views`** with the metric topic — check for a canonical
   view. If found, pull its SQL and compare against the query being verified.

3. **Audit the SQL or result** against the three traps. Produce a short
   finding for each trap: pass, flag, or not-applicable.

4. If a flag is raised and quantification is useful, **`execute_sql`** to show
   the magnitude of the difference (e.g. gross vs. net gap, UTC vs. PST gap).

5. **Present the verdict**: pass list, any flags with explanation and fix,
   and a one-line confidence statement ("This figure is gross revenue,
   UTC-bounded, completed orders only — consistent with Chord defaults").

## Presenting the verdict

Structure the output as a short audit, not a wall of caveats:

```
✓ Order status filter: completed orders only
✓ Currency: USD (warehouse default)
⚠ Revenue basis: GROSS — partial refunds not deducted. Net figure: $X (difference: $Y).
⚠ Timezone: UTC boundaries used. Shopify admin (PST) would show $Z for the same period.
   To align with admin: [SQL snippet]
```

If everything passes: "All checks passed — this figure is [gross/net] revenue,
UTC-bounded, completed orders only."

Don't raise traps that aren't applicable to the metric. A customer-count query
doesn't need a gross/net check.

## Failure modes

- **MCP tools not available** — the `mcp__chord__*` tools are missing.
  The chord MCP server isn't registered. Tell the user to run:
  ```
  claude mcp add chord --transport http https://mcp.staging.chorddemo.copilot.chord.co/mcp/ --scope user
  ```

- **No SQL to audit** — if the user is verifying a number from the Hub UI
  (not from a SQL query), focus on Trap 1 (ask whether they need gross or net)
  and Trap 3 (ask whether they're comparing to Shopify admin). Skip Trap 2
  (the Hub pipeline always filters to completed orders).

- **`search_instructions` returns nothing** — the tenant hasn't stored custom
  conventions. Fall back to Chord's defaults as documented above.
