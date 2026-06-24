---
name: chord-activation-health
description: Report the health of all audience syncs — destinations connected, syncs active/errored/paused, last successful run, and error details — by chaining the three activation tools. Use when the user asks why a Klaviyo list, Meta audience, or other destination isn't updating, or asks for sync status, activation health, or when data last synced.
---

# Chord Activation Health — sync diagnostic workflow

You have access to `mcp__chord__*` tools exposed by the chord MCP server.

This skill diagnoses the activation layer: the pipeline that pushes data from
the Chord warehouse to downstream marketing platforms (Klaviyo, Meta Ads,
Google Ads, TikTok, Braze, Attentive, Iterable, etc.).

Use the tools below in order — each step narrows from broad health summary to
specific failure details. Stop as soon as you have enough to answer the user's
question.

## Tools

- **`get_activation_summary`** — high-level health snapshot: total destinations
  connected, total syncs configured, counts of active / paused / errored syncs.
  Start here every time.

- **`list_audience_syncs`** — full sync list with per-sync name, target
  destination, and current status (active / paused / error). Use to identify
  which specific syncs are unhealthy.

- **`get_sync_run_history(sync_id)`** — recent run log for one sync: timestamps,
  success/failure status, records processed, and error messages. Call this for
  every sync that is in error or paused, and for any sync where the user suspects
  stale data even if the status shows "active."

- **`list_data_sources`** — Fivetran connector list with sync status. Use only
  when a sync appears healthy (no errors) but data is still stale — the problem
  may be upstream of the activation layer.

## Workflow

1. **`get_activation_summary`** — get the counts. If everything is active and
   healthy, say so and stop.

2. If any syncs are errored or paused: **`list_audience_syncs`** — identify
   which syncs and which destinations are affected.

3. For each unhealthy sync (error or paused): **`get_sync_run_history(sync_id)`**
   — surface the most recent error message, the timestamp of the last successful
   run, and the count of consecutive failures.

4. If a specific sync is named by the user (e.g. "why isn't my Klaviyo VIP
   list updating?"): go directly to `list_audience_syncs` to find the sync ID,
   then `get_sync_run_history`. Do not skip to step 4 without first confirming
   the sync exists.

5. If all syncs appear active but data is still stale: **`list_data_sources`**
   to check whether a Fivetran source is behind schedule. Cross-reference the
   expected freshness windows below.

## Expected freshness (Chord defaults)

Use these when interpreting whether a delay is normal or a problem:

| Layer | Expected latency |
|---|---|
| Shopify → Snowflake (Fivetran) | ~15 minutes |
| Klaviyo → Snowflake (Fivetran) | ~1 hour (metrics) / ~6 hours (campaigns) |
| Snowflake → dbt marts | ~8–12 minutes after Fivetran completes |
| Snowflake → Destinations (Census) | Configurable per sync: hourly / 6h / 12h / daily |
| **End-to-end (order placed → data in Klaviyo)** | ~20–30 min (fast path) / ~6–7 hours (slow path) |

A sync that shows "active" but last ran 36 hours ago is not healthy — status
reflects the last run result, not whether the schedule is being honored.
Always check `completed_at` on the most recent run record.

## Silent failure pattern

Census alerts after **3 consecutive failures**. A sync can accumulate 2 silent
failures before any alert fires. When `get_sync_run_history` shows 1–2 recent
failures with an "active" overall status, flag it: "This sync has had N recent
failures but has not yet triggered an alert. Watch it."

## Presenting the diagnosis

Lead with the actionable finding, not the raw data:

```
Activation summary: 8 syncs active, 1 errored, 0 paused.

Errored sync: "Meta Ads — At-Risk Churners"
  Last successful run: 2026-06-07 03:14 UTC
  Consecutive failures: 3
  Error: "Meta API rate limit exceeded (code 17)"
  Recommended action: Check your Meta API quota in Hub under CDP > Syncs,
  or reduce sync frequency to every 12h.

All other syncs are healthy. Most recent run timestamps are within expected
freshness windows.
```

If everything is healthy, keep it short: "All 8 syncs are active. Most recent
runs are within expected freshness windows."

## Failure modes

- **MCP tools not available** — the `mcp__chord__*` tools are missing.
  The chord MCP server isn't registered. Tell the user to run:
  ```
  claude mcp add chord --transport http https://mcp.staging.chorddemo.copilot.chord.co/mcp/ --scope user
  ```

- **Activation tools return empty** — `list_audience_syncs` returns no results.
  This means no syncs have been configured yet, or the user's tenant doesn't
  have activation enabled. Tell the user to check Hub under CDP > Syncs and
  confirm at least one sync is set up.

- **`get_sync_run_history` returns no runs for a sync** — the sync was just
  created and has never run, or runs are not yet being logged for this tenant.
  Surface this as "No run history available — this sync may not have executed
  yet."
