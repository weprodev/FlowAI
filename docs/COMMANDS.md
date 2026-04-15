# FlowAI Commands Reference

## Core Commands

| Command | Purpose |
|---------|---------|
| `fai` | Short alias for `flowai` — `bin/fai` symlinks to `bin/flowai`. |
| `flowai init` | Initialise `.flowai/` and bootstrap Spec Kit (`.specify/`) via `uvx`. |
| `flowai start [--headless] [--skip-graph]` | Boot the tmux session. Prompts to build knowledge graph if missing. `--skip-graph` bypasses the graph requirement (degraded mode). |
| `flowai kill` / `flowai stop` | Terminate the session. |
| `flowai status` | Show session, config, Spec Kit, skills, MCP, and knowledge graph health. |
| `flowai logs [<phase>]` | View the output buffer of a running phase (defaults to `master`). Output is paginated with `less`. |
| `flowai run [<phase>]` | Run a pipeline phase. Omit `<phase>` for an interactive menu. |
| `flowai graph <subcommand>` | Knowledge graph management — see [Knowledge Graph](#knowledge-graph) below. |
| `flowai models list [<tool>\|all]` | Print valid model ids from `models-catalog.json`. Tools: `gemini`, `claude`, `cursor`, `copilot`, `all`. |
| `flowai validate` | Check `.flowai/config.json` model fields against `models-catalog.json`. Alias: `flowai config validate`. |
| `flowai mcp list` | Show configured MCP servers. If `.flowai/mcp.json` is missing, creates a minimal one from defaults. Preserves existing files without modifying or merging. |
| `flowai skill add \| apply \| remove \| list` | Manage skills assigned to pipeline roles. Interactive menu includes GitHub (skills.sh), Context7, Local directory, or manual path. |
| `flowai role list \| edit \| set-prompt \| reset` | Manage role prompt overrides. `edit` copies a bundled role for local editing; `set-prompt` points a role at a project file. |
| `flowai help` | Global usage overview. |
| `flowai version` / `--version` | Print version string from `VERSION`. |

---

## Pipeline Phases

Run individually with `flowai run <phase>` or all together via `flowai start`:

| Phase | Command | Waits for |
|-------|---------|-----------|
| Spec | `flowai run spec` | _(none — first phase)_ |
| Plan | `flowai run plan` | `spec.ready` |
| Tasks | `flowai run tasks` | `plan.ready` |
| Implement | `flowai run implement` (alias: `impl`) | `tasks.ready` |
| Review | `flowai run review` | `impl.code_complete.ready` (Implement touches this when code is ready for QA) |

Each phase runs the AI, then prompts for human approval before emitting its `.ready` signal. Rejecting returns to the AI loop after a revision signal.

---

## Technical Internals

### Interactive vs Headless

Commands check `[ -t 0 ]` for TTY presence. Under CI or `FLOWAI_TESTING=1`, gum menus and confirmations are bypassed to prevent deadlocks.

### Spec Kit (Specify) Integration

`flowai init` bootstraps Spec Kit via:

```bash
uvx --from git+https://github.com/github/spec-kit.git specify init . --script sh
```

Falls back to a bundled seed when the network or `uv` is unavailable.

### Configuration

`.flowai/config.json` controls which CLI and model each phase uses. See [TOOLS.md](TOOLS.md) for the full key reference and model resolution order.

**Before `flowai start`:** model fields are validated against `models-catalog.json` (unless `FLOWAI_TESTING=1`, `FLOWAI_SKIP_CONFIG_VALIDATE=1`, or `FLOWAI_ALLOW_UNKNOWN_MODEL=1`). Run **`flowai validate`** after editing the config.

### Skill Local Paths

Register a project-relative skill directory (committed to your repo, shared with the team):

```bash
flowai skill add   # choose "Local directory (project path)" in the interactive menu
```

This appends to `skills.paths[]` in `.flowai/config.json`. Skills inside that directory are discovered automatically. See [ARCHITECTURE.md](ARCHITECTURE.md#skills--roles-resolution) for the full resolution chain.

### Role Overrides

```bash
flowai role list                          # see which roles have overrides
flowai role edit team-lead                # copy bundled → .flowai/roles/team-lead.md, open in $EDITOR
flowai role set-prompt reviewer docs/roles/reviewer.md  # point a role at a repo file
flowai role reset team-lead               # remove all overrides, revert to bundled
```

See [ARCHITECTURE.md](ARCHITECTURE.md#skills--roles-resolution) for the complete 5-tier role prompt resolution chain.

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `FLOWAI_ALLOW_UNKNOWN_MODEL=1` | Skip catalog model validation at runtime. |
| `FLOWAI_SKIP_CONFIG_VALIDATE=1` | Skip start-time config validation only. |
| `FLOWAI_PHASE_TIMEOUT_SEC=N` | Hard timeout (seconds) for phase signal waits. `0` = unlimited (default). |
| `FLOWAI_PLAIN_TERMINAL=1` | Disable carriage-return redraws (Master pipeline line, phase wait spinner). Use for readable scrollback in tmux/Terminal after long sessions. |
| `FLOWAI_TESTING=1` | Enable CI mode: bypass gum, auto-select dirs, skip dependency checks. |
| `FLOWAI_TEST_SKIP_AI=1` | Contract-test mode: phase scripts exit 0 before invoking AI. |
| `FLOWAI_SKIP_GRAPH=1` | Skip graph enforcement in `flowai start` (same as `--skip-graph` flag). |
| `FLOWAI_PHASE_EXPECTED_DURATION_SEC=N` | Master scope check threshold (seconds). When a phase exceeds this, Master AI verifies the agent is on track. Default: `300` (5 min). |
| `FLOWAI_PANE_MIN_HEIGHT=N` | Minimum rows for inactive **phase** panes when only one pipeline pane is emphasized. Default: `3`. |
| `FLOWAI_DASHBOARD_MAXIMIZE_FOCUS=1` | Dashboard layout only: when multiple phase panes exist (impl + review, etc.), make the **focused** phase tall and shrink the others to `FLOWAI_PANE_MIN_HEIGHT`. Default is **off** — phase panes **share height evenly** so two active agents get equal rows. |
| `FLOWAI_GRAPH_CONTEXT_REPORT_LINES=N` | Lines of `GRAPH_REPORT.md` embedded in the `[FLOWAI KNOWLEDGE GRAPH]` system-prompt block (default **200**). Lower = fewer tokens; higher = more on-map detail without opening the file. |
| `FLOWAI_GRAPH_CONTEXT_MAX_CHARS=N` | Optional **second** cap on the embedded report excerpt (characters, after the line limit). **0** = disabled (default). Use when reports have very long lines so the prompt stays bounded — same idea as read-budget limits in compact CLI wrappers. |

### Event Log Configuration

Control how pipeline events are formatted when injected into agent prompts:

```json
{
  "event_log": {
    "prompt_format": "compact"
  }
}
```

| Value | Tokens/event | Description |
|-------|-------------|-------------|
| `compact` | ~8 | Deduplicated, short `HH:MM` timestamps (default) |
| `minimal` | ~3 | `phase:event` only — maximum token savings |
| `full` | ~20 | Raw JSONL — maximum detail |

---

## Knowledge Graph

FlowAI maintains a **compiled knowledge graph** of your project at `.flowai/wiki/`.
Every pipeline agent reads this graph as its primary navigation layer, replacing
blind file searches with structured, token-efficient codebase context.

### Subcommands

```bash
flowai graph build [--force]       # Build the full graph (--force ignores cache)
flowai graph update                 # Incremental update (changed files only)
flowai graph chronicle              # Mine git log → IMPLEMENTS edges + spec evolution
flowai graph ingest <file>          # Ingest a document → update wiki pages
flowai graph query "<question>"     # Query + file answer back as a wiki page
flowai graph lint [--structural]    # Coverage analysis: unimplemented specs, zombies, debt
flowai graph status                 # Show node/edge counts, age, staleness
flowai graph report                 # Read GRAPH_REPORT.md in the pager
flowai graph rollback [--latest]    # Interactive version browser (--latest for CI/scripts)
```

### Graph outputs at `.flowai/wiki/`

| File | Contents |
|---|---|
| `GRAPH_REPORT.md` | God nodes, communities, insights, suggested queries. **Start here.** |
| `graph.json` | Full graph: nodes, edges, provenance (`EXTRACTED`/`INFERRED`/`AMBIGUOUS`), metadata |
| `index.md` | Content catalog — every wiki page with a one-line summary |
| `log.md` | Append-only operation log (`## [date] op | detail`) |

### Integration with `flowai start`

`flowai start` enforces that a graph exists:
- If **no graph** → prompts to build one (default: yes)
- If **graph is stale** (>24h by default) → warns and suggests `flowai graph update`
- Use `--skip-graph` / `FLOWAI_SKIP_GRAPH=1` for degraded mode (not recommended)

### Agent context injection

When a graph exists, every agent automatically receives a navigation block in its
system prompt directing it to read `GRAPH_REPORT.md` before accessing raw files.
This is a **platform-level** capability — all roles and phases get it regardless
of which skills are assigned.

The `graph-aware-navigation` skill (bundled, assigned to all roles) teaches agents
the full navigation protocol: `GRAPH_REPORT.md → index.md → wiki/ → graph.json → source files`.

### Team sharing

By default `.flowai/wiki/` is gitignored (local graph). To share with the team:
1. Remove `.flowai/wiki/` from `.gitignore`
2. Commit `.flowai/wiki/`
3. Run `flowai graph update` in CI to keep it fresh

For full conceptual documentation see [GRAPH.md](GRAPH.md).

