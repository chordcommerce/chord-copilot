---
name: chord-copilot
description: Answer data questions against the Chord warehouse using the chord MCP tools. Use when the user asks about warehouse data, schema, metrics, revenue, customers, orders, products, subscriptions, sessions, attribution, Shopify, Klaviyo, Iterable, or any saved/canonical query — anything that would be answered by SQL against the Chord data model. Triggers include 'how many', 'show me', 'top N', 'last month', 'last quarter', 'trend', 'breakdown', 'compare', 'revenue', 'orders', 'customers'. Supports two modes: Analyst (Claude retrieves context and writes SQL via get_sql_context + execute_sql) and Copilot (full Hub pipeline delegated via ask). Requires the chord-copilot MCP server to be connected; if the mcp__chord__* tools are not available, tell the user to connect the server.
---

# Chord Copilot — data-question workflows

You have access to `mcp__chord__*` tools exposed by the chord-copilot MCP server.
Reach for them automatically — without being asked — whenever the user's request
involves warehouse data, schema, saved queries, or product documentation. Do not
fall back to hand-written SQL or guess at table names when these tools are available.

Two modes are available. Default to **Analyst** mode; switch to **Copilot** mode
when the user wants a packaged answer with a natural-language summary.

---

## Tool reference

### Retrieval bundle

- **`get_sql_context`** — the primary retrieval tool. One call runs schema DDL
  lookup, historical SQL examples, user-defined instructions, and memory in
  parallel and returns a single structured payload:
  `{schema_ddl, sql_pairs, instructions, memories}`. Use this before writing any
  SQL — `schema_ddl` gives exact column names and types, `instructions` contain
  always-apply project conventions (filters, joins, revenue/COGS rules,
  test-order exclusion), and `sql_pairs` provide few-shot examples.

### Individual retrieval (targeted lookups)

- **`search_schema`** — semantic search over table descriptions. Useful for
  exploring what data exists or finding tables beyond the top-k returned by
  `get_sql_context`.
- **`search_sql_pairs`** — find past question/SQL pairs. Use when you need
  additional examples not covered by `get_sql_context`.
- **`search_saved_views`** — check whether a user-blessed canonical query
  already answers the question. Prefer an existing view over inventing SQL.
  Run this as a separate step alongside or after `get_sql_context`.
- **`search_instructions`** — pull always-apply SQL guidance. Covered by
  `get_sql_context` in the standard workflow; call this directly only for
  targeted scope queries (e.g. `scope="chart"`).
- **`search_documentation`** — for "how do I…" questions about the Chord
  Copilot product itself (global, not project-scoped).

### Execution

- **`preview_table`** — peek at a handful of rows from a known table.
  Capped at 100 rows; use for shape/sanity checks, not analysis.
- **`execute_sql`** — run a read-only query (SELECT/UNION/INTERSECT/EXCEPT
  only; capped at 10 000 rows). Pass `validate_only=True` to parse-check
  without executing.

### Hub pipeline

- **`ask`** — delegates the full pipeline to the Chord Hub: SQL generation →
  warehouse execution → natural-language summary in one call. Returns
  `{sql, summary, threadId}` for data questions or
  `{type: "NON_SQL_QUERY", explanation, threadId}` for general questions.
  Pass `thread_id` to continue an existing conversation thread.

---

## Mode 1 — Analyst (Claude writes SQL)

**Use this by default.** Claude retrieves context from the warehouse data model
and then writes SQL grounded in that context.

1. **`get_sql_context`** — single call, returns schema DDL, SQL examples,
   instructions, and memory. Supplies everything needed to write correct SQL.
2. **`search_saved_views`** — check for a canonical user-blessed query that
   already answers the question. Prefer it over writing new SQL if one exists.
3. **Draft SQL** grounded in the context from steps 1–2. For non-trivial
   queries, call `execute_sql` with `validate_only=True` first.
4. **`execute_sql`** — run the query and return rows.

Run step 2 in parallel with step 1 since they're independent.

---

## Mode 2 — Copilot (Hub pipeline)

**Use when the user wants a packaged answer** — SQL, results, and a
natural-language summary — without stepping through the workflow manually.
Also use when the user says "ask Chord" or "use the Hub".

1. **`ask(question, thread_id?)`** — one call that handles the full pipeline.
2. If the response contains `sql` and `summary`: present the summary as the
   answer. Offer to show the SQL or run follow-up questions. Pass the returned
   `threadId` as `thread_id` in any follow-up `ask` call.
3. If the response is `NON_SQL_QUERY`: present the `explanation` field directly.

---

## Choosing a mode

| Situation | Mode |
|-----------|------|
| User asks a data question and wants to see/verify the SQL | Analyst |
| Multi-step or iterative query refinement | Analyst |
| Complex joins, window functions, or custom logic | Analyst |
| User wants a quick packaged answer with a summary | Copilot |
| Follow-up questions in a thread ("and last month?") | Copilot |
| User says "ask Chord" / "use the Hub" | Copilot |

---

## How to present the answer

- **Cite instructions applied.** Name which instructions from `get_sql_context`
  you followed — and which you intentionally skipped, with reasoning.
  (Example: "Used `NET_REVENUE` because the user asked for 'revenue', not
  'net revenue' — instruction #37 reserves the COGS+shipping formula for
  explicit 'net revenue' asks.")
- **Name saved views.** If a saved view answered the question, cite its
  `view_id` so the user can find it in the Hub.
- **Surface errors verbatim.** If the engine returns an error, show the error
  text before attempting a fix — the user often recognizes it.

---

## Failure modes

- **MCP tools not available** — the `mcp__chord__*` tools are missing from the
  tool list. The chord-copilot MCP server isn't registered with Claude Code.
  Tell the user to run:
  ```
  claude mcp add chord-copilot --transport http https://mcp.<instance>.copilot.chord.co/mcp/ --scope user
  ```
  (replacing `<instance>` with their tenant slug). Fall back to whatever
  workflow they normally use until then.

- **`ask` returns an error about Hub not configured** — the MCP server is
  running without `WREN_UI_URL` set. This means the Copilot mode is unavailable;
  switch to Analyst mode instead.

- **Engine unreachable** — `execute_sql` / `preview_table` return a connection
  error. The retrieval tools (`get_sql_context`, `search_saved_views`) may still
  work — complete steps 1–3 of the Analyst workflow and stop at "drafted SQL,
  ready to run once the engine is up."
