---
name: chord-copilot
description: Answer data questions against the Chord warehouse using the chord MCP retrieval and execution tools. Use when the user asks about warehouse data, schema, metrics, revenue, customers, orders, products, subscriptions, sessions, attribution, Shopify, Klaviyo, or Iterable — anything answered by SQL against the Chord data model. Triggers include 'how many', 'show me', 'top N', 'last month', 'trend', 'breakdown', 'compare', 'revenue', 'orders', 'customers'. For text-to-SQL, ALWAYS call `ask` (Chord's end-to-end pipeline) first — including for complex or multi-part questions — then verify and run the returned SQL with execute_sql. Only author SQL by hand after `ask` has run (it failed, or you've read its SQL and need to adjust it). Requires the chord-copilot MCP server; if the mcp__chord__* tools aren't available, fall back to the user's normal workflow and tell them to connect the server.
---

# Chord Copilot — data-question workflow

You have access to a set of `mcp__chord__*` tools exposed by the chord-copilot
MCP server. Reach for them automatically — without being asked — whenever the
user's request involves the project's warehouse data, schema, saved queries,
or product documentation. Do not fall back to hand-written SQL or guess at
table names when these tools are available.

## The `ask`-first rule (non-negotiable)

For any text-to-SQL question, **call `ask` first.** This holds regardless of
how complex the question is. A multi-part question (cohort definition +
benchmark + projections, say) is *not* a reason to skip `ask` and author SQL
by hand — complexity is a reason to **inspect** what `ask` returns, not a
reason to bypass it. There is no path to hand-authored SQL that does not pass
through `ask` first.

Common failure mode to avoid: the question looks intricate, hand-authoring
feels more controllable, so you jump straight to `search_schema` /
`execute_sql`. Don't. Call `ask` with the full question first. If the logic
genuinely needs decomposition, pass `histories` (prior `{question, sql}` turns)
or `custom_instruction`, or call `ask` on sub-questions — but `ask` runs first
either way.

## When to use which tool

- **`ask`** — first stop for every text-to-SQL question, simple or complex.
  Runs Chord's full text-to-SQL pipeline (schema/instruction retrieval, SQL
  generation, validation, self-healing) and returns grounded SQL. Returns
  `{status, type, sql, rephrased_question, sql_generation_reasoning,
  retrieved_tables, assistant_text, error, trace_id}`. When `type` is
  `TEXT_TO_SQL`, use the returned `sql` (after verifying it — see below)
  rather than authoring your own, then run it with `execute_sql`. When `type`
  is `GENERAL`, the answer is already in `assistant_text` and there's no SQL
  to run. Pass `histories` (prior `{question, sql}` turns, oldest first) for
  follow-ups and `custom_instruction` for one-off guidance. The call blocks
  until the pipeline finishes (up to a few minutes).
- **`search_instructions`** — pull always-apply SQL guidance the user has
  stored (filters, joins, casing rules, revenue/COGS conventions, test-order
  exclusion, segmentation conventions). Run this to **verify `ask`'s SQL**
  before presenting results, and again before finalizing any hand-authored
  SQL.
- **`search_schema`** — discover which tables exist and what they contain.
  For the fallback authoring path, or to inspect what `ask` used.
- **`search_sql_pairs`** — find past question/SQL pairs that resemble the
  user's question. Useful as few-shot grounding before drafting new SQL.
- **`search_saved_views`** — check whether a user-blessed canonical query
  already answers the question. Prefer an existing view over inventing SQL.
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

For a text-to-SQL question:

1. `ask` — run Chord's end-to-end text-to-SQL pipeline. Always first.
   - `type` is `TEXT_TO_SQL`: proceed to step 2 (verify), then step 3 (run).
   - `type` is `GENERAL`: present `assistant_text` — you're done, no SQL
     to run.
2. **Verify before trusting** — do not present `ask`'s results without
   checking its SQL against stored conventions. `ask` is fast and consistent
   but it can quietly pick the wrong definition. At minimum, confirm:
   - **Revenue basis** — gross vs net. Does `ask`'s choice match what the
     user asked for? Don't let a net AOV answer a gross-framed question (or
     vice versa). Keep the threshold, the LTV, and the AOV on the *same*
     basis.
   - **Test-order exclusion** — is `ORDER_IS_TEST` filtered out where the
     stored convention requires it?
   - **Segmentation / purity logic** — for "exclusively X" segments, check
     the exclusion is airtight (e.g. literal "Missing Product Type" values
     are not the same as `NULL`; a NULL-only check leaks).
   - **Cohort windows** — are recency / lapse / reactivation windows
     anchored where the question implies (per-customer last order vs a fixed
     calendar snapshot), and is the cohort set wide enough to support a
     "lowest / highest observed" claim?
   Run `search_instructions` (and `search_schema` if needed) to do this. If
   `ask`'s SQL deviates, adjust it (drop to the authoring path) before
   running.
3. `execute_sql` — run the verified `sql` to return rows.

### Fallback: author or adjust the SQL yourself

Enter this path only **after `ask` has run** — either it failed
(`status` is `failed`), or you've read its SQL in step 2 and need to fix a
deviation. Do not start here.

1. `search_schema` — discover relevant tables.
2. `search_saved_views` and `search_sql_pairs` — in parallel, look for a
   canonical query or close prior example.
3. `search_instructions` — pull always-apply SQL guidance.
4. Draft SQL grounded in the above.
5. `execute_sql` (optionally with `validate_only=True` first for non-trivial
   queries) to return rows.

Run independent retrieval steps in parallel.

## How to present the answer

- When `ask` produced the SQL, summarize its `sql_generation_reasoning`,
  name the `retrieved_tables` it grounded on, **and state the verification
  you did in step 2** — which conventions you checked and whether `ask`'s
  SQL matched them. Don't just describe what `ask` did; confirm it was
  right.
- State the definitional choices that drive the headline numbers explicitly
  (gross vs net, AOV denominator, window anchoring, what's included/excluded
  from a segment), since these are where two reasonable queries diverge most.
- When you authored or adjusted the SQL yourself, cite which instructions you
  applied — and which you intentionally skipped, with reasoning. (Example:
  "Used `GROSS_REVENUE` because the user asked for 'gross revenue', not
  'net' — instruction #20 reserves the refund-adjusted formula for explicit
  'net revenue' asks.")
- If a saved view answered the question, name the `view_id` so the user can
  find it in Copilot.
- If the engine returns an error, surface the error text verbatim before
  attempting a fix — the user often recognizes it.
