---
name: chord-copilot
description: Answer data questions against the Chord warehouse by delegating to the Chord Hub pipeline end-to-end. Use when the chord-copilot MCP server is connected (mcp__chord_copilot__* tools are available) and the user asks about warehouse data — revenue, orders, customers, products, subscriptions, sessions, attribution, Shopify, Klaviyo, Iterable, or any metric in the Chord data model. Triggers include 'how many', 'show me', 'top N', 'last month', 'last quarter', 'trend', 'breakdown', 'compare', 'revenue', 'orders', 'customers'. The Hub handles intent classification, SQL generation, warehouse execution, and narrative summary — Claude surfaces the result.
---

# Chord Copilot — Hub pipeline workflow

You have access to `mcp__chord_copilot__*` tools exposed by the chord-copilot MCP
server. Use them automatically whenever the user's request involves warehouse data.

The Hub pipeline is the same engine that powers the Chord Hub UI and the Chord
Slack bot, so results are consistent across all surfaces.

## Tools

- **`ask`** — the primary tool. One call handles the full pipeline: intent
  classification → SQL generation → warehouse execution → natural-language
  summary. Returns one of:
  - `{sql, summary, threadId}` — for data questions: the generated SQL, a
    human-readable answer, and a thread ID for follow-ups.
  - `{type: "NON_SQL_QUERY", explanation, threadId}` — for general questions
    the Hub can't answer with SQL.
  Pass `thread_id` to continue an existing conversation thread.

- **`preview_table`** — peek at up to 100 rows from a known table. Use for
  quick shape checks when the user wants to see example data without asking
  a full question.

## Workflow

1. **`ask(question, thread_id?)`** — pass the user's question as-is.
2. If the response contains `sql` and `summary`:
   - Present the `summary` as the answer.
   - Offer to show the underlying SQL if the user wants to verify it.
   - Pass the returned `threadId` as `thread_id` in any follow-up `ask` call
     to maintain conversation context.
3. If the response is `NON_SQL_QUERY`: present the `explanation` directly.

## Follow-up conversations

Thread context is maintained server-side via `threadId`. Always pass it back:

```
first answer  → {sql, summary, threadId: "t1"}
follow-up     → ask("And last month?", thread_id="t1")
```

## Failure modes

- **MCP tools not available** — the `mcp__chord_copilot__*` tools are missing.
  The chord-copilot MCP server isn't registered. Tell the user to run:
  ```
  claude mcp add chord-copilot --transport http https://mcp.<instance>.chord.co/mcp/copilot/ --scope user
  ```

- **`ask` returns Hub not configured** — the MCP server is running without
  `WREN_UI_URL`. The Copilot pipeline is unavailable; tell the user to check
  their deployment configuration.
