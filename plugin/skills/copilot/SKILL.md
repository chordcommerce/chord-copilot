---
name: chord-copilot
description: Answer data questions against the Chord warehouse by delegating to the Chord GraphQL pipeline end-to-end. Use when the chord MCP server is connected (mcp__chord__* tools are available) and the user asks about warehouse data — revenue, orders, customers, products, subscriptions, sessions, attribution, Shopify, Klaviyo, Iterable, or any metric in the Chord data model. Triggers include 'how many', 'show me', 'top N', 'last month', 'last quarter', 'trend', 'breakdown', 'compare', 'revenue', 'orders', 'customers'. The pipeline handles intent classification, SQL generation, warehouse execution, and narrative summary — Claude surfaces the result.
---

# Chord Copilot — GraphQL pipeline workflow

You have access to `mcp__chord__*` tools exposed by the chord MCP server.
Use them automatically whenever the user's request involves warehouse data.

Use the Copilot-tier tools for this workflow: `ask` and `preview_table`.
Do not call `get_sql_context`, `execute_sql`, or write SQL directly — the
pipeline handles all of that.

The `ask` tool calls wren-ui's GraphQL API directly, running the same pipeline
that powers the Chord Hub UI and Slack bot. Results are consistent across all
surfaces.

## Tools

- **`ask`** — the primary tool. One call handles the full pipeline: SQL
  generation → warehouse execution → natural-language summary. Returns one of:
  - `{sql, summary, threadId}` — for data questions.
  - `{type: "NON_SQL_QUERY", explanation, threadId: null}` — for general
    questions the pipeline can't answer with SQL.
  Pass `thread_id` (integer) to continue an existing conversation thread.

- **`preview_table`** — peek at up to 100 rows from a known table. Use for
  quick shape checks without asking a full question.

## Workflow

1. **`ask(question, thread_id?)`** — pass the user's question as-is.
2. If the response contains `sql` and `summary`:
   - Present the `summary` as the answer.
   - Offer to show the underlying SQL if the user wants to verify it.
   - Pass the returned `threadId` as `thread_id` in any follow-up `ask` call.
3. If the response is `NON_SQL_QUERY`: present the `explanation` directly.

## Follow-up conversations

Thread context is maintained server-side. Always pass the integer `threadId`
back as `thread_id` for follow-ups:

```
first call    → ask("How many orders last month?")
               ← {sql, summary, threadId: 42}
follow-up     → ask("And last quarter?", thread_id=42)
```

## Failure modes

- **MCP tools not available** — the `mcp__chord__*` tools are missing.
  The chord MCP server isn't registered. Tell the user to run:
  ```
  # local dev (wren-ai-service):
  claude mcp add chord --transport http http://localhost:5555/mcp/ --scope user
  # deployed — use your wren-ai-service URL:
  ```

- **`ask` returns error about wren-ui not configured** — the MCP server is
  running without `WREN_UI_URL`. Tell the user to check their deployment config.
