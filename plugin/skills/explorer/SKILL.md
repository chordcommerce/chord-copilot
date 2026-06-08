---
name: chord-explorer
description: Browse and discover the Chord data model — tables, saved views, and documentation — without writing SQL. Use when the chord MCP server is connected (mcp__chord__* tools are available) and the user wants to understand what data exists, find canonical queries, or get oriented in the schema. Triggers include 'what tables', 'what data do we have', 'show me the schema', 'find a view for', 'what is in', 'how is X defined', 'browse', 'explore', 'documentation'.
---

# Chord Explorer — schema discovery workflow

You have access to `mcp__chord__*` tools exposed by the chord MCP server.
Use them automatically when the user wants to explore, understand, or navigate
the data model rather than answer a specific analytical question.

Use the Explorer-tier tools for this workflow: `search_schema`,
`search_saved_views`, `preview_table`, and `search_documentation`.
Do not call `execute_sql`, `get_sql_context`, or `ask` — Explorer is
discovery only, not analysis.

## Tools

- **`search_schema`** — semantic search over table descriptions. Returns table
  names, short descriptions, and similarity scores. Use to answer "what tables
  exist for X?" or to orient the user in an unfamiliar dataset.

- **`search_saved_views`** — find canonical, user-blessed named queries that
  match the user's topic. Returns the originating question, a short summary,
  the SQL behind the view, and its `view_id`.

- **`preview_table`** — peek at up to 100 rows from a known table. Useful for
  understanding the shape and content of a table.

- **`search_documentation`** — search the Chord Copilot user-guide for pages
  matching the query. For "how do I…" questions about the product itself.

## Workflow

**Exploring what data exists:**
1. `search_schema` with the user's topic — identify relevant tables.
2. `preview_table` on interesting tables to show example rows.
3. `search_saved_views` to surface any canonical queries in this area.

**Finding a saved view:**
1. `search_saved_views` — primary tool. The `sql` field shows exactly how
   the metric is computed; cite the `view_id` so the user can find it in the Hub.

**Product documentation:**
1. `search_documentation` — returns page paths and content excerpts.

## Presenting findings

- Summarize which tables are available and what they contain.
- Link to relevant saved views by `view_id`.
- Be explicit about what Explorer cannot do: if the user wants to run a query
  or get numbers, they need the Analyst or Copilot tier.

## Failure modes

- **MCP tools not available** — the `mcp__chord__*` tools are missing.
  The chord MCP server isn't registered. Tell the user to run:
  ```
  # local dev (wren-ai-service):
  claude mcp add chord --transport http http://localhost:5555/mcp/ --scope user
  # deployed — use your wren-ai-service URL:
  ```
