---
name: chord-analyst
description: Answer data questions against the Chord warehouse using retrieval-grounded SQL. Use when the chord MCP server is connected (mcp__chord__* tools are available) and the user asks about warehouse data — revenue, orders, customers, products, subscriptions, sessions, attribution, Shopify, Klaviyo, Iterable, or any saved/canonical query. Triggers include 'how many', 'show me', 'top N', 'last month', 'last quarter', 'trend', 'breakdown', 'compare', 'revenue', 'orders', 'customers'. Claude retrieves full context (DDL, instructions, memory, examples) before writing SQL.
---

# Chord Analyst — retrieval-grounded SQL workflow

You have access to `mcp__chord__*` tools exposed by the chord MCP server.
Reach for them automatically — without being asked — whenever the user's
request involves warehouse data, schema, saved queries, or product documentation.

Use the Analyst-tier tools for this workflow. Do not call `ask` — that is the
Copilot tier. Claude writes SQL here; Chord provides the context.

## Tools

### Primary retrieval

- **`get_sql_context`** — the most important tool. One call runs schema DDL
  lookup, historical SQL examples, user-defined instructions, and memory in
  parallel and returns a single structured payload:
  `{schema_ddl, sql_pairs, instructions, memories}`.
  - `schema_ddl`: exact column names and types — always use this before writing SQL.
  - `instructions`: always-apply project conventions (test-order exclusion,
    revenue/COGS definitions, required filters, join keys). Apply all that are
    relevant; cite which you used and which you skipped (with reasoning).
  - `sql_pairs`: few-shot examples grounding your SQL in patterns that have
    worked before.

### Supplemental retrieval

- **`search_schema`** — semantic search over table descriptions. Useful for
  exploring beyond the top-k tables returned by `get_sql_context`.
- **`search_sql_pairs`** — additional historical Q&A examples.
- **`search_saved_views`** — canonical, user-blessed queries. Prefer an existing
  view over writing new SQL if one covers the question.
- **`search_instructions`** — targeted instruction lookup by scope (e.g.
  `scope="chart"`). Covered by `get_sql_context` for the standard `sql` scope.
- **`search_documentation`** — Chord Copilot user-guide pages. For
  "how do I…" questions about the product itself.

### Execution

- **`execute_sql`** — run a read-only SELECT query (capped at 10 000 rows).
  Pass `validate_only=True` to parse-check without executing.
- **`preview_table`** — peek at up to 100 rows from a known table.
  For shape/sanity checks, not analysis.

## Workflow

1. **`get_sql_context`** and **`search_saved_views`** in parallel — retrieval
   bundle plus canonical view check in one round trip.
2. **Draft SQL** grounded in `schema_ddl`, `instructions`, and `sql_pairs`. If
   a saved view already answers the question, prefer it and cite its `view_id`.
3. For non-trivial queries, **`execute_sql validate_only=True`** to catch errors
   before execution.
4. **`execute_sql`** to run and return rows.

## Presenting the answer

- **Cite instructions applied.** Name which instructions from `get_sql_context`
  you followed and which you intentionally skipped, with reasoning.
- **Name saved views.** If a view answered the question, cite its `view_id`.
- **Surface errors verbatim.** Show the engine error before attempting a fix.

## Failure modes

- **MCP tools not available** — the `mcp__chord__*` tools are missing.
  The chord MCP server isn't registered. Tell the user to run:
  ```
  claude mcp add chord --transport http https://mcp.<instance>.chord.co/mcp/ --scope user
  ```

- **Engine unreachable** — `execute_sql` / `preview_table` return a connection
  error. Retrieval tools (`get_sql_context`, `search_saved_views`) may still
  work — complete steps 1–3 and stop at "drafted SQL, ready to run once the
  engine is up."
