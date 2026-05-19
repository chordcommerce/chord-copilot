# chord-copilot

The Claude Code plugin + standalone skill for answering data questions
against the Chord warehouse using the Chord Copilot MCP server.

This repo ships **two install paths from the same source of truth** — pick
whichever fits your client:

- **Claude Code plugin** — one command. Registers the MCP server *and*
  installs the skill. Recommended for Claude Code users.
- **Standalone skill installer** — a `curl | bash` script that drops
  `SKILL.md` into `~/.claude/skills/chord-copilot/`. Useful for Claude
  Desktop or any MCP client that reads `SKILL.md` but doesn't support
  Claude Code plugins. Requires a separate `claude mcp add` step.

The MCP **server** itself (the wren-ai-service implementation) lives in a
separate Chord repo. This repo only contains the user-facing onboarding
artifacts.

## Install (Claude Code plugin)

Two commands. The first adds this repo as a plugin marketplace; the
second installs the chord-copilot plugin from it.

```
/plugin marketplace add chordcommerce/chord-copilot
/plugin install chord@chord
```

That installs:

1. The `chord-copilot` MCP server (via the bundled `.mcp.json`) — no
   separate `claude mcp add` step needed.
2. The `copilot` workflow skill (from `skills/copilot/SKILL.md`), which
   appears in Claude Code as `chord:copilot`.

Restart Claude Code and you're done.

The plugin's `.mcp.json` points at `http://localhost:5555/mcp/` by
default. If your wren-ai-service runs elsewhere, edit the installed
copy under `~/.claude/plugins/` or override via `claude mcp` commands.

## Install (standalone skill)

Two steps, in order:

### 1. Register the MCP server

```bash
# Local wren-ai-service:
claude mcp add chord-copilot --transport http http://localhost:5555/mcp/ --scope user

# Or any deployed instance: swap in your wren-ai-service host.
```

### 2. Install the skill

```bash
curl -fsSL https://raw.githubusercontent.com/chordcommerce/chord-copilot/main/install.sh | bash
```

Restart your client.

## `install.sh` options

```
./install.sh [--scope user|project] [--project-dir <path>] [--ref <ref>] [--force]
```

- `--scope user` (default) → `~/.claude/skills/chord-copilot/`.
- `--scope project` → `<project-dir>/.claude/skills/chord-copilot/`.
- `--project-dir <path>` — defaults to `pwd`.
- `--ref <branch|tag|sha>` — pin which version of SKILL.md to fetch
  (also `CHORD_SKILL_REF` env var). Defaults to `main`.
- `--force` — overwrite an existing install without prompting.

## Verifying

```bash
claude mcp list             # should show `chord-copilot` connected
ls ~/.claude/skills/         # standalone install path
ls ~/.claude/plugins/        # plugin install path
```

Then ask Claude *"How many orders did we have last month?"* — the skill
should auto-trigger and walk through the retrieval-grounded SQL workflow:
`search_schema` → `search_saved_views` / `search_sql_pairs` →
`search_instructions` → draft SQL → `execute_sql`.

## Repo layout

```
chord-copilot/
├── .claude-plugin/
│   └── marketplace.json         # marketplace manifest (referenced by `/plugin marketplace add`)
├── plugin/                       # the chord plugin (referenced from marketplace.json as a git-subdir source)
│   ├── .claude-plugin/
│   │   └── plugin.json           # plugin manifest
│   ├── .mcp.json                 # MCP server registration (bundled with plugin install)
│   └── skills/
│       └── copilot/
│           └── SKILL.md          # canonical workflow guidance (plugin namespace: chord:copilot)
├── install.sh                    # standalone installer (fallback for non-plugin clients)
├── README.md
└── LICENSE
```

`SKILL.md` is the canonical source of truth. Both the plugin install path
and the standalone `install.sh` consume it from `plugin/skills/copilot/`.

The plugin's `.mcp.json` lives under `plugin/`, not at the repo root.
This stops Claude Code from auto-detecting it as project-scope MCP
config and stomping on it while you work in the repo.

## License

MIT. See [LICENSE](LICENSE).
