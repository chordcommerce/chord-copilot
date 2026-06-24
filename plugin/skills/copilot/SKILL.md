---
name: chord-copilot
description: "Answer data questions against the Chord warehouse using the chord MCP retrieval and execution tools. Use when the user asks about warehouse data, schema, metrics, revenue, customers, orders, products, subscriptions, sessions, attribution, Shopify, Klaviyo, Iterable, or any saved/canonical query — i.e. anything that would be answered by SQL against the Chord data model. Triggers include 'how many', 'show me', 'top N', 'last month', 'last quarter', 'trend', 'breakdown', 'compare', 'revenue', 'orders', 'customers'. Walks the agent through the default retrieval-grounded SQL workflow: search_schema → search_saved_views / search_sql_pairs → search_instructions → draft SQL → execute_sql. Requires the chord-copilot MCP server to be connected; if the mcp__chord__* tools are not available, fall back to the user's normal workflow and tell them to connect the server."
---

# Chord Copilot — data-question workflow

You have access to a set of `mcp__chord__*` tools exposed by the chord-copilot
MCP server. Reach for them automatically — without being asked — whenever the
user's request involves the project's warehouse data, schema, saved queries,
or product documentation. Do not fall back to hand-written SQL or guess at
table names when these tools are available.

## When to use which tool

- **`search_schema`** — first stop for any data question. Discover which
  tables exist and what they contain before writing SQL.
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
- **`list_tenants`** — list the tenants (Chord organizations) you have access
  to. Returns `[{name, slug, current}]` where `current` marks the tenant your
  requests route to right now. Every other tool automatically targets the
  current tenant's warehouse — you never pass a tenant per call.
- **`switch_tenant`** — change which tenant subsequent tool calls route to.
  Pass `slug` (from `list_tenants`) for an organization you're a member of;
  every later call (`ask`, `execute_sql`, `search_*`, `preview_table`) then
  targets that tenant's warehouse for the rest of the session — no reconnect
  or re-auth needed. Rejected if you're not a member of the requested tenant.

## Working across tenants

The server routes every request to the **current tenant's** warehouse — it
picks this for you from your authenticated account, so don't try to route by
hand. If you're unsure which organization you're operating in, call
`list_tenants` first (it marks the `current` one). When the user asks to work
against a different organization they belong to, call `switch_tenant` with its
`slug`; the new routing sticks for the rest of the session.

## Default workflow

For a data question:

1. `search_schema` — discover relevant tables.
2. `search_saved_views` and `search_sql_pairs` — in parallel, look for a
   canonical query or close prior example.
3. `search_instructions` — pull always-apply SQL guidance.
4. Draft SQL grounded in the above.
5. `execute_sql` (optionally with `validate_only=True` first for non-trivial
   queries) to return rows.

Run independent retrieval steps in parallel.

## How to present the answer

- Cite which instructions you applied — and which you intentionally
  skipped, with reasoning. (Example: "Used plain `NET_REVENUE` because
  the user asked for 'revenue', not 'net revenue' — instruction #37
  reserves the COGS+shipping formula for explicit 'net revenue' asks.")
- If a saved view answered the question, name the `view_id` so the user
  can find it in Copilot.
- If the engine returns an error, surface the error text verbatim before
  attempting a fix — the user often recognizes it.
