---
name: chord-raw
description: Answer data questions against the Chord warehouse using only table descriptions and SQL execution. Use when the chord MCP server is connected (mcp__chord__* tools are available) and the user asks about warehouse data — revenue, orders, customers, products, subscriptions, sessions, or any metric that lives in the Chord data model. Claude discovers tables via search_schema and writes SQL itself with no additional context.
---

# Chord Raw — data-question workflow

You have access to `mcp__chord__*` tools exposed by the chord MCP server.

Use only the Raw-tier tools for this workflow: `search_schema` and `execute_sql`.
Do not call `get_sql_context`, `ask`, or other tools — they are not part of the
Raw tier.

## Tools

- **`search_schema`** — semantic search over table descriptions. Returns table
  names, short descriptions, and similarity scores. Use this to discover which
  tables are relevant before writing SQL. You will not get column DDL — reason
  from common naming conventions and validate with `execute_sql validate_only=True`
  before running non-trivial queries.

- **`execute_sql`** — run a read-only SELECT query against the warehouse. Only
  SELECT/UNION/INTERSECT/EXCEPT are accepted; capped at 10 000 rows.
  Pass `validate_only=True` to parse-check without executing.

## Workflow

1. **`search_schema`** — find tables relevant to the question.
2. **Draft SQL** from the table descriptions. Use common Snowflake column-naming
   conventions. For non-trivial queries, call `execute_sql` with
   `validate_only=True` first to catch binding errors early.
3. **`execute_sql`** — run the query and return rows.

## Presenting the answer

- Show the SQL you wrote alongside the results so the user can verify it.
- If the engine returns an error, show it verbatim before attempting a fix.
- If a query binding fails (unknown column), try a narrower `search_schema` call
  to find the correct column name, then revise.

## Failure modes

- **MCP tools not available** — the `mcp__chord__*` tools are missing.
  The chord MCP server isn't registered with Claude Code. Tell the user to run:
  ```
  # local dev (wren-ai-service):
  claude mcp add chord --transport http http://localhost:5555/mcp/ --scope user
  # deployed — use your wren-ai-service URL:
  ```
