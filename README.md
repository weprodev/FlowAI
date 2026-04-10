<p align="center">
  <img src="logo.png" alt="FlowAI" width="420" />
</p>

<p align="center">
  <strong>Spec-driven multi-agent orchestration for the terminal.</strong><br />
  Coordinate AI agents across your entire development lifecycle — from spec to review — in one tmux session.
</p>

<p align="center">
  <code>bash</code> + <code>jq</code> + <code>tmux</code> &mdash; no Python, no Docker, no external runtime.
</p>

---

## What It Does

FlowAI orchestrates multiple AI agent CLIs (Gemini, Claude, Cursor, Copilot) through a **five-phase pipeline**:

```
Spec  →  Plan  →  Tasks  →  Implement  →  Review
```

Each phase runs in its own tmux pane with a dedicated role, waits for human approval before handing off, and shares context through a **compiled knowledge graph** and **real-time event log**. The master agent monitors the entire pipeline and intervenes on failures.

**You bring the AI tools. FlowAI wires them together.**

---

## Quick Start

```bash
# Install
curl -fsSL https://raw.githubusercontent.com/WeProDev/FlowAI/main/install.sh | bash

# Init a project
cd /path/to/your/repo
flowai init

# Launch the pipeline
flowai start
```

Or clone and `make install`. Alias: `fai` = `flowai`.

---

## Requirements

| Dependency | Purpose |
|------------|---------|
| `bash`, `jq`, `tmux`, `gum` | Runtime |
| `uv` | Bootstraps [GitHub Spec Kit](https://github.github.io/spec-kit/) during `flowai init` |
| At least one AI CLI | `gemini`, `claude`, `cursor`, or `copilot` — install separately |

---

## Key Capabilities

### Master Orchestration
The master agent creates the spec interactively, then enters a **monitoring loop** — polling the event log, displaying progress, and re-engaging on review rejections. All downstream agents receive pipeline context automatically.

### Knowledge Graph
A persistent, compiled graph of your codebase (`.flowai/wiki/`) that every agent reads before touching files. Structural extraction for **Bash, Python, TypeScript/JS, and Go** — no LLM required. Optional semantic pass for deeper analysis. Includes community detection via label propagation, graph versioning with rollback, and structural lint.

```bash
flowai graph build          # full build
flowai graph update         # incremental (changed files only)
flowai graph lint           # health check
flowai graph rollback       # restore previous version
```

### Event Log (Message Bus)
Append-only JSONL at `.flowai/events.jsonl` gives every agent visibility into pipeline activity. Configurable prompt injection format (`compact`, `minimal`, `full`) to control token usage.

### Roles & Skills
12 specialist roles (backend, frontend, security, DevOps, etc.) with a **5-tier resolution chain**. 9 bundled skills (TDD, debugging, planning, etc.) with a **4-tier resolution chain**. Both are fully customizable per-project.

### Review Rejection Loop
When review fails, the review agent writes structured rejection context. On re-run, the implement agent focuses only on failed items — no full re-implementation.

---

## Configuration

All config lives in `.flowai/config.json`:

```json
{
  "master": { "tool": "gemini", "model": "gemini-2.5-pro" },
  "pipeline": { "plan": "team-lead", "impl": "backend-engineer", "review": "reviewer" },
  "graph": { "scan_paths": ["src", "docs", "specs"], "versions_to_keep": 5 },
  "event_log": { "prompt_format": "compact" }
}
```

Validate anytime: `flowai validate`. Model IDs are checked against the bundled `models-catalog.json`.

---

## Documentation

| Guide | What It Covers |
|-------|----------------|
| **[Architecture](docs/ARCHITECTURE.md)** | Pipeline, signals, plugins, event log, master monitoring, skills/roles resolution, source layout |
| **[Commands](docs/COMMANDS.md)** | Every CLI command, environment variables, event log config |
| **[Knowledge Graph](docs/GRAPH.md)** | Build passes, community detection, versioning, chronicle, SDD integration, configuration |
| **[Supported Tools](docs/TOOLS.md)** | Tool plugin API, model catalog, config keys, vendor references |

---

## Testing

```bash
make audit    # shellcheck + 103 tests (unit, integration, plugin compliance, signals)
```

103 tests across 8 suites: CLI entrypoint, lifecycle, skills, roles, knowledge graph, event log, tool plugins, and phase signals. All bash-native — no test framework dependencies.

---

## License

MIT — see [`LICENSE`](LICENSE).
