---
name: chord-copilot
description: Answer data questions against the Chord warehouse using the chord MCP retrieval and execution tools. Use when the user asks about warehouse data, schema, metrics, revenue, customers, orders, products, subscriptions, sessions, attribution, Shopify, Klaviyo, Iterable, or any saved/canonical query — i.e. anything that would be answered by SQL against the Chord data model. Triggers include 'how many', 'show me', 'top N', 'last month', 'last quarter', 'trend', 'breakdown', 'compare', 'revenue', 'orders', 'customers'. For a text-to-SQL question, calls `ask` (Chord's end-to-end text-to-SQL pipeline) then runs the returned SQL with execute_sql, falling back to the retrieval-grounded authoring workflow (search_schema → search_saved_views / search_sql_pairs → search_instructions → draft SQL → execute_sql) when ask fails or the SQL needs inspection. Requires the chord-copilot MCP server to be connected; if the mcp__chord__* tools are not available, fall back to the user's normal workflow and tell them to connect the server.
---

# Chord Copilot — data-question workflow

You have access to a set of `mcp__chord__*` tools exposed by the chord-copilot
MCP server. Reach for them automatically — without being asked — whenever the
user's request involves the project's warehouse data, schema, saved queries,
or product documentation. Do not fall back to hand-written SQL or guess at
table names when these tools are available.

## When to use which tool

- **`ask`** — first stop for a text-to-SQL question. Runs Chord's full
  text-to-SQL pipeline (schema/instruction retrieval, SQL generation,
  validation, self-healing) and returns grounded SQL. Returns `{status,
  type, sql, rephrased_question, sql_generation_reasoning,
  retrieved_tables, assistant_text, error, trace_id}`. When `type` is
  `TEXT_TO_SQL`, use the returned `sql` rather than authoring your own,
  then run it with `execute_sql`. When `type` is `GENERAL`, the answer is
  already in `assistant_text` and there's no SQL to run. Pass `histories`
  (prior `{question, sql}` turns, oldest first) for follow-ups and
  `custom_instruction` for one-off guidance. The call blocks until the
  pipeline finishes (up to a few minutes).
- **`search_schema`** — for the fallback authoring path (or to inspect
  what `ask` used). Discover which tables exist and what they contain
  before writing SQL.
- **`search_sql_pairs`** — find past question/SQL pairs that resemble the
  user's question. Useful as few-shot grounding before drafting new SQL.
- **`search_saved_views`** — check whether a user-blessed canonical query
  already answers the question. Prefer an existing view over inventing SQL.
- **`search_instructions`** — pull any always-apply SQL guidance the user
  has stored (filters, joins, casing rules, revenue/COGS conventions,
  test-order exclusion). Run this before finalizing SQL.
- **`search_documentation`** — for "how do I…" questions about the Chord
  Copilot product itself (global, not project-scoped).
- **`preview_table`** — peek at a handful of rows from a known table.
  Capped at 100 rows; use for shape/sanity checks, not analysis.
- **`execute_sql`** — run a read-only query (SELECT/UNION/INTERSECT/EXCEPT
  only; capped at 10000 rows). Pass `validate_only=True` to parse-check
  without executing.

## Default workflow

For a text-to-SQL question:

1. `ask` — run Chord's end-to-end text-to-SQL pipeline.
   - `type` is `TEXT_TO_SQL`: use the returned `sql`.
   - `type` is `GENERAL`: present `assistant_text` — you're done, no SQL
     to run.
2. `execute_sql` — run the `sql` from step 1 to return rows.

### Fallback: author the SQL yourself

If `ask` fails (`status` is `failed`), or you need to inspect or adjust the
SQL it produced, drop to the retrieval-grounded authoring workflow:

1. `search_schema` — discover relevant tables.
2. `search_saved_views` and `search_sql_pairs` — in parallel, look for a
   canonical query or close prior example.
3. `search_instructions` — pull always-apply SQL guidance.
4. Draft SQL grounded in the above.
5. `execute_sql` (optionally with `validate_only=True` first for non-trivial
   queries) to return rows.

Run independent retrieval steps in parallel.

## How to present the answer

- When `ask` produced the SQL, summarize its `sql_generation_reasoning`
  and name the `retrieved_tables` it grounded on, so the user can see how
  the query was derived.
- When you authored the SQL yourself (fallback path), cite which
  instructions you applied — and which you intentionally skipped, with
  reasoning. (Example: "Used plain `NET_REVENUE` because the user asked
  for 'revenue', not 'net revenue' — instruction #37 reserves the
  COGS+shipping formula for explicit 'net revenue' asks.")
- If a saved view answered the question, name the `view_id` so the user
  can find it in Copilot.
- If the engine returns an error, surface the error text verbatim before
  attempting a fix — the user often recognizes it.

