---
name: chord-daily-insights
description: Run the nightly insights digest — pull the five core commerce signals (revenue health, channel ROAS, repeat rate/LTV, LTV/CAC efficiency, VIP slippage), flag anything crossing a threshold, write narrative sentences, and post to Slack. Use when asked to run the daily digest, generate insights, or post the nightly report. Also runs automatically on its cron schedule.
---

# Chord Daily Insights — nightly digest workflow

You have access to `mcp__chord__*` tools and `mcp__slack__*` tools.

This skill runs five analytics queries, evaluates each result against flagging
thresholds, generates plain-English insight sentences, and posts the digest to
Slack. It is designed to run nightly without human input.

Follow every step in order. Do not skip retrieval. Do not post to Slack until
all five signals are evaluated.

---

## Step 0 — Load tenant context

Before running any queries:

1. **`search_instructions`** (scope: `sql`) — load the tenant's conventions.
   Look for any stored threshold overrides:
   - `ltv_cac_target` (default: 3.0)
   - `repeat_rate_floor` (default: 0.60)
   - `roas_gap_threshold` (default: 0.20 — flag when best/worst channel ROAS
     gap exceeds this)
   - `vip_slip_threshold` (default: 0.05 — flag when slipping VIPs exceed 5%
     of active VIP base)
   - `revenue_change_threshold` (default: -0.01 — flag on any QoQ decline)
   - `slack_channel` — the channel ID to post to (required; fail loudly if
     not found and no channel was specified by the user)
   - `comparison_period` — `quarter` (default) or `month`

2. **`search_saved_views`** with query `"daily insights digest revenue ROAS
   repeat LTV"` — check for any canonical views that cover these signals.
   If found, prefer them over writing new SQL.

Set the two comparison periods:
- **Current period:** current full quarter-to-date (or month-to-date if
  `comparison_period = month`). Use `DATE_TRUNC('quarter', CURRENT_DATE())`.
- **Prior period:** the immediately preceding full quarter (or month).
  Use `DATEADD('quarter', -1, DATE_TRUNC('quarter', CURRENT_DATE()))`.

---

## Signal 1 — Revenue health (EXECUTIVE)

**Query via `ask`:**
> "What is net revenue and contribution margin percentage for the current
> quarter versus the prior quarter? Show the dollar amounts and the
> period-over-period change."

**Flagging threshold:** Flag as WATCH if:
- QoQ revenue change < `revenue_change_threshold` (default -1%)
- OR CM% dropped more than 2 percentage points QoQ

**Metrics to capture for the digest:**
- `net_revenue_current`, `net_revenue_prior`, `revenue_change_pct`
- `cm_pct_current`, `cm_pct_prior`

---

## Signal 2 — Channel ROAS comparison (ACQUISITION)

**Query via `execute_sql`** (use `search_saved_views("roas by channel")` first):

```sql
WITH spend AS (
    SELECT
        channel,
        SUM(spend) AS total_spend
    FROM fct_marketing_spend
    WHERE spend_date >= DATE_TRUNC('quarter', CURRENT_DATE())
    GROUP BY channel
),
revenue AS (
    SELECT
        acquisition_channel AS channel,
        SUM(o.net_total) AS attributed_revenue
    FROM fct_orders o
    JOIN dim_customers c ON o.customer_id = c.customer_id
    WHERE o.order_date >= DATE_TRUNC('quarter', CURRENT_DATE())
      AND o.status = 'completed'
      AND o.is_first_order = TRUE
    GROUP BY acquisition_channel
)
SELECT
    s.channel,
    s.total_spend,
    r.attributed_revenue,
    ROUND(r.attributed_revenue / NULLIF(s.total_spend, 0), 2) AS roas
FROM spend s
LEFT JOIN revenue r ON s.channel = r.channel
WHERE s.total_spend > 0
ORDER BY roas DESC
```

**Flagging threshold:** Flag as WATCH if:
- The gap between the highest and lowest ROAS channel exceeds
  `roas_gap_threshold` (default 0.20x), indicating reallocation opportunity
- OR any channel ROAS is below 1.0x (spend exceeds attributed revenue)

**Metrics to capture:**
- Top two channels by ROAS and their values
- Weakest channel name and ROAS

---

## Signal 3 — Repeat rate & LTV (RETENTION)

**Query via `ask`:**
> "What is the repeat purchase rate and average customer lifetime value for
> the current quarter versus the prior quarter?"

**Flagging threshold:** Flag as WATCH if:
- Repeat rate < `repeat_rate_floor` (default 60%)
- OR repeat rate declined more than 2pp QoQ
- OR avg LTV declined QoQ

**Metrics to capture:**
- `repeat_rate_current`, `avg_ltv_current`

---

## Signal 4 — LTV/CAC efficiency (ACQUISITION)

**Query via `execute_sql`** (use `search_saved_views("ltv cac ratio")` first):

```sql
WITH cac AS (
    SELECT
        SUM(spend) / NULLIF(COUNT(DISTINCT c.customer_id), 0) AS cac
    FROM fct_marketing_spend ms
    JOIN dim_customers c
        ON DATE_TRUNC('quarter', c.first_order_date)
           = DATE_TRUNC('quarter', CURRENT_DATE())
    WHERE ms.spend_date >= DATE_TRUNC('quarter', CURRENT_DATE())
),
ltv AS (
    SELECT AVG(lifetime_value) AS avg_ltv
    FROM dim_customers
    WHERE first_order_date >= DATE_TRUNC('quarter', CURRENT_DATE())
)
SELECT
    ROUND(ltv.avg_ltv / NULLIF(cac.cac, 0), 2) AS ltv_cac_ratio,
    ltv.avg_ltv,
    cac.cac
FROM ltv CROSS JOIN cac
```

**Flagging threshold:** Flag as WATCH if:
- LTV/CAC ratio < `ltv_cac_target` (default 3.0)

**Metrics to capture:**
- `ltv_cac_ratio`, `avg_ltv`, `cac`

---

## Signal 5 — VIP slippage (RETENTION)

**Query via `execute_sql`** (use `search_saved_views("vip slipping platinum gold")` first):

```sql
WITH vip_prior AS (
    -- VIPs who placed an order in the prior quarter
    SELECT DISTINCT o.customer_id
    FROM fct_orders o
    JOIN dim_customers c ON o.customer_id = c.customer_id
    WHERE o.order_date >= DATEADD('quarter', -1, DATE_TRUNC('quarter', CURRENT_DATE()))
      AND o.order_date <  DATE_TRUNC('quarter', CURRENT_DATE())
      AND o.status = 'completed'
      AND c.segment = 'vip'
),
vip_current AS (
    -- VIPs who have placed an order in the current quarter
    SELECT DISTINCT o.customer_id
    FROM fct_orders o
    JOIN dim_customers c ON o.customer_id = c.customer_id
    WHERE o.order_date >= DATE_TRUNC('quarter', CURRENT_DATE())
      AND o.status = 'completed'
      AND c.segment = 'vip'
),
vip_active AS (
    SELECT COUNT(*) AS active_count FROM dim_customers WHERE segment = 'vip'
)
SELECT
    (SELECT COUNT(*) FROM vip_prior) AS vip_ordered_prior_period,
    (SELECT COUNT(*) FROM vip_current) AS vip_ordered_current_period,
    (SELECT active_count FROM vip_active) AS total_active_vips,
    (SELECT COUNT(*) FROM vip_prior WHERE customer_id NOT IN
        (SELECT customer_id FROM vip_current)) AS slipping_vips
```

**Flagging threshold:** Flag as WATCH if:
- `slipping_vips / vip_ordered_prior_period` > `vip_slip_threshold`
  (default 5%)

**Metrics to capture:**
- `total_active_vips`, `slipping_vips`, `vip_ordered_prior_period`

---

## Metric verification pass

Before composing the message, run the `chord-metric-verify` checklist on
the revenue figures mentally:
- Signals 1, 3, 4 use net revenue / LTV — confirm `net_total` or
  `lifetime_value` (gross) was used and note which in the digest footer.
- All queries use `status = 'completed'` — verify this before posting.
- Note: all figures use UTC date boundaries. If the brand's Shopify admin
  is PST-configured, the numbers may differ slightly from admin figures.

---

## Composing the insight sentences

For each signal that was flagged WATCH, write one insight sentence following
this structure:

> **[Key metric with value]** — [plain-English interpretation of what it
> means] — [single highest-leverage action recommended].

Rules:
- Lead with the number, not the category label.
- The second clause explains *why it matters*, not just *what happened*.
- The third clause is one specific action, not a general suggestion.
- Keep each sentence to one line — no sub-bullets.
- Signals that pass all thresholds still appear in the digest but without
  a WATCH flag and with a shorter format: "[Metric]: [value] — on track."

Example outputs:
- WATCH: "Revenue fell -1% to $4.4M vs. prior quarter — spend efficiency
  and channel mix need review."
- WATCH: "Meta is the weakest paid channel at 2.26x ROAS — Google at 2.47x
  is the clear candidate to absorb reallocated budget."
- OK: "Repeat rate: 63% — on track vs. 60% floor."

---

## Posting to Slack

Post using `mcp__slack__slack_send_message` to the `slack_channel` loaded
in Step 0.

Format the message as follows (standard Slack markdown):

```
*🔍 Chord Daily Insights — [Brand Name] — [Date]*
_[Current period] vs. [Prior period]_

━━━━━━━━━━━━━━━━━━━━━━

*EXECUTIVE*
[⚠️ WATCH / ✅ OK]  [Insight sentence 1]
`NET REVENUE $X.XM  CM% XX%`

*ACQUISITION*
[⚠️ WATCH / ✅ OK]  [Channel ROAS insight sentence]
`[TOP CHANNEL] ROAS X.XXx  [WEAK CHANNEL] ROAS X.XXx`

[⚠️ WATCH / ✅ OK]  [LTV/CAC insight sentence]
`LTV/CAC X.XXx  AVG LTV $XXX`

*RETENTION*
[⚠️ WATCH / ✅ OK]  [Repeat rate insight sentence]
`REPEAT RATE XX.X%  AVG LTV $XXX`

[⚠️ WATCH / ✅ OK]  [VIP slippage insight sentence]
`VIP ACTIVE X,XXX  SLIPPING X,XXX`

━━━━━━━━━━━━━━━━━━━━━━
_Revenue figures: net (refund-adjusted), UTC date boundaries, completed orders only._
```

Use ⚠️ for WATCH signals and ✅ for signals within target. Omit signals
that returned no data (engine error, missing table) rather than posting
zeros — note any skipped signals in a `_Skipped: ..._` line at the bottom.

---

## Error handling

- **`ask` returns NON_SQL_QUERY for a signal:** Fall back to `execute_sql`
  with the explicit SQL patterns in this skill. If that also fails, skip the
  signal and note it as skipped.
- **`execute_sql` returns a connection error:** Note the signal as skipped.
  Do not post zeros. Post the digest with available signals only.
- **`slack_channel` not found in instructions and not specified by user:**
  Stop. Ask: "Which Slack channel should I post the insights digest to?"
- **All five signals fail:** Do not post. Report the failure to the user
  and suggest checking the MCP server connection.

---

## Failure modes

- **MCP tools not available** — the `mcp__chord__*` tools are missing.
  Tell the user to run:
  ```
  claude mcp add chord --transport http https://mcp.staging.chorddemo.copilot.chord.co/mcp/ --scope user
  ```
- **Slack tools not available** — the Slack MCP server isn't connected.
  Run the digest and print the formatted output to the terminal instead.
