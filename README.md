<p align="center">
  <img src="logo.png" alt="FlowAI" width="420" />
</p>

<p align="center">
  <strong>Spec-driven multi-agent orchestration for the terminal.</strong><br />
  Coordinate AI agents across your entire development lifecycle — from spec to review — in one tmux session.
</p>

<p align="center">
  <code>bash</code> + <code>jq</code> + <code>tmux</code> — no Python, no Docker, no external runtime.<br />
  Works on <strong>macOS</strong>, <strong>Linux</strong>, and <strong>Windows</strong> (Git Bash).
</p>


AI coding assistants are powerful, but using them effectively across a full feature lifecycle is hard. You end up copy-pasting context between tools, re-explaining your codebase to every agent, burning tokens on redundant context, and hoping the implementation matches the spec.

**FlowAI solves this by turning your terminal into a structured, multi-agent pipeline:**

- **One spec, many agents** — Write the spec once. FlowAI routes it through plan, tasks, implementation, and review automatically.
- **Right agent for the job** — Assign Gemini for planning, Claude for implementation, any tool for review. Each phase gets the best model for the task.
- **Knowledge graph = less tokens, better code** — Your codebase is pre-analyzed into a compiled graph. Agents get precise, relevant context instead of scanning thousands of files. Less noise, fewer tokens, higher quality output.
- **Skills make agents smarter** — Attach behavioral skills (TDD, systematic debugging, code review) that constrain how agents work, not just what they produce.
- **MCP servers extend reach** — Connect agents to GitHub PRs, databases, documentation, and file systems through the Model Context Protocol.
- **Human in the loop** — Every phase waits for your approval. You stay in control while agents do the heavy lifting.

---

## What It Does

FlowAI orchestrates multiple AI agent CLIs through a **five-phase pipeline**:

```
Spec  →  Plan  →  Tasks  →  Implement  →  Review
```

Each phase runs in its own tmux pane with a dedicated **role**, attached **skills**, and pre-loaded **knowledge graph context**. The master agent monitors the entire pipeline, tracks progress via the event log, and intervenes on failures.

**You bring the AI tools. FlowAI wires them together.**

---

## Quick Start

### Install

**macOS / Linux:**
```bash
curl -fsSL https://raw.githubusercontent.com/WeProDev/FlowAI/main/install.sh | bash
```

**Windows (Git Bash):**
```bash
curl -fsSL https://raw.githubusercontent.com/WeProDev/FlowAI/main/install.sh | PREFIX="$HOME/.local" bash
```

### Set up a project

```bash
cd /path/to/your/repo
flowai init       # interactive wizard: pick AI provider, configure roles, scaffold editor configs
flowai start      # builds knowledge graph → launches the tmux pipeline
```

> **Tip:** `fai` is a shortcut for `flowai` — same commands, faster to type.

### Update

```bash
flowai update             # self-update to latest release
flowai update --check     # check without installing
```

---

## Requirements

| Dependency | Purpose | Install |
|------------|---------|---------|
| `bash` | Runtime | Pre-installed on macOS/Linux |
| `jq` | JSON processing (graph, config) | `brew install jq` / `apt install jq` |
| `tmux` | Multi-pane session management | `brew install tmux` / `apt install tmux` |
| `gum` | Interactive menus & approval prompts | `brew install gum` |
| At least one AI CLI | The agents that do the work | [Gemini CLI](https://github.com/google-gemini/gemini-cli) · [Claude Code](https://docs.anthropic.com/en/docs/claude-code) · [Cursor](https://cursor.com) · [GitHub Copilot](https://github.com/features/copilot) |

`flowai init` validates all dependencies and exits with platform-specific install instructions if anything is missing.

---

## Features

### 🤖 Multi-Agent Orchestration

Assign different AI tools and models to each pipeline phase. FlowAI manages the handoff, context sharing, and approval gates between them.

```json
{
  "master":   { "tool": "gemini", "model": "gemini-2.5-pro" },
  "pipeline": {
    "plan":   { "role": "team-lead",        "tool": "gemini" },
    "impl":   { "role": "backend-engineer", "tool": "claude" },
    "review": { "role": "reviewer",         "tool": "gemini" }
  }
}
```

Use Gemini for planning (fast, large context), Claude for implementation (precise, code-heavy), and rotate reviewers — all in the same session.

---

### 🧠 Knowledge Graph — Better Code, Fewer Tokens

Traditional AI workflows dump your entire codebase into the context window. FlowAI pre-compiles a **structural knowledge graph** of your project — functions, classes, imports, specs, and their relationships — so agents get targeted, relevant context instead of raw file listings.

**The result:** agents produce higher-quality output because they understand your architecture, and you burn fewer tokens because irrelevant files are excluded.

```bash
flowai graph build          # full build (Bash, Python, TS/JS, Go, Markdown, JSON)
flowai graph update         # incremental — only re-processes changed files
flowai graph lint           # health check: orphaned specs, zombie code, coverage gaps
flowai graph query "..."    # ask questions about your codebase structure
flowai graph rollback       # restore a previous graph version
```

Features:
- **Structural extraction** for Bash, Python, TypeScript/JS, and Go — no LLM required
- **Community detection** via label propagation — identifies clusters and god-objects
- **Structural lint** — detects unimplemented specs, zombie code, and test gaps
- **Spec traceability** — links specs to implementations via `SPECIFIES` / `IMPLEMENTS` edges
- **Incremental builds** with SHA-based caching — sub-second updates on large codebases
- **Graph versioning** with configurable rollback depth

---

### 🎭 Roles — Specialized Agent Personas

Each pipeline phase is assigned a **role** — a markdown prompt that defines the agent's expertise, constraints, and quality standards. FlowAI ships with 12 specialist roles:

| Role | Focus |
|------|-------|
| `master` | Pipeline orchestration, monitoring, failure recovery |
| `team-lead` | Architecture decisions, planning, technical direction |
| `backend-engineer` | Go/Python/Node backend, DDD, API design |
| `frontend-engineer` | React, TypeScript, UI components, accessibility |
| `api-engineer` | REST/GraphQL contracts, versioning, documentation |
| `security-engineer` | Auth, encryption, vulnerability assessment |
| `devops-engineer` | CI/CD, Docker, Kubernetes, infrastructure |
| `qa-engineer` | Test strategy, coverage, edge cases |
| `data-engineer` | Databases, migrations, query optimization |
| `performance-engineer` | Profiling, caching, load testing |
| `docs-writer` | Technical writing, API docs, tutorials |
| `reviewer` | Code review, standards enforcement, approval |

**Fully customizable:** Drop a `.flowai/roles/plan.md` or `.flowai/roles/backend-engineer.md` into your project and it overrides the bundled role. A 5-tier resolution chain ensures the most specific prompt always wins.

```bash
flowai role list                           # see all available roles
flowai role edit backend-engineer          # customize a role for this project
flowai role set-prompt plan ./my-plan.md   # use a custom prompt file
flowai role reset plan                     # revert to bundled default
```

---

### ⚡ Skills — Behavioral Constraints for Agents

Skills are reusable markdown documents that teach agents **how to work**, not just what to build. They enforce patterns like test-driven development, systematic debugging, and structured code review.

**9 bundled skills** from [obra/superpowers](https://github.com/obra/superpowers):

| Skill | What it enforces |
|-------|-----------------|
| `test-driven-development` | Write tests first, implement second, verify always |
| `systematic-debugging` | Root cause analysis before any fix attempt |
| `writing-plans` | Structured planning before implementation |
| `executing-plans` | Follow plans step-by-step, no skipping |
| `requesting-code-review` | Structured review requests with context |
| `verification-before-completion` | Verify all changes before marking done |
| `subagent-driven-development` | Decompose work into focused sub-tasks |
| `finishing-a-development-branch` | Clean up, squash, document before merge |
| `graph-aware-navigation` | Use the knowledge graph for codebase navigation |

```bash
flowai skill add obra/superpowers/systematic-debugging     # install from GitHub
flowai skill add context7 obra/superpowers/writing-plans   # install with MCP context
flowai skill list                                          # see installed skills
flowai skill remove systematic-debugging                   # remove a skill
```

Skills are resolved through a **4-tier chain**: installed → project-relative → bundled → skip. Project-local skills in `.flowai/skills/` always win.

---

### 🔌 MCP Servers — Extend Agent Capabilities

Connect your agents to external tools and data sources through the [Model Context Protocol](https://modelcontextprotocol.io/). FlowAI manages the MCP configuration so every agent in the pipeline has access.

**Built-in catalog:**

| Server | What it provides |
|--------|-----------------|
| `context7` | Real-time library documentation (npm, PyPI, Go) |
| `github` | GitHub API — PRs, issues, branches, code search |
| `gitlab` | GitLab API — MRs, issues, pipelines |
| `filesystem` | Local file system operations |
| `postgres` | PostgreSQL database introspection |

```bash
flowai mcp add github          # add from built-in catalog
flowai mcp add context7        # add library docs server
flowai mcp list                # see configured servers
flowai mcp remove github       # remove a server
```

The MCP config is written to `.flowai/mcp.json` and automatically loaded by supported AI CLIs.

---

### 🔄 Review Rejection Loop

When the review phase rejects an implementation, the review agent writes structured rejection context — what failed, why, and what to fix. On re-run, the implement agent focuses **only on failed items**, not a full re-implementation. This dramatically reduces iteration time and token usage.

---

### 📝 Editor Integration

`flowai init` scaffolds project-level context files for your AI editor, ensuring agents understand your project from the start:

| Editor | Config file | Created by |
|--------|------------|------------|
| Claude Code | `.claude/CLAUDE.md` | `flowai init` |
| Gemini | `.gemini/GEMINI.md` | `flowai init` |
| Cursor | `.cursor/rules/flowai.mdc` | `flowai init` |
| GitHub Copilot | `.github/copilot-instructions.md` | `flowai init` |

Files are created once and never overwritten — safe to customize.

---

### 📊 Event Log — Pipeline Visibility

An append-only JSONL log at `.flowai/events.jsonl` gives every agent real-time visibility into what's happening across the pipeline. Configurable prompt injection format controls token usage:

| Format | Tokens | Best for |
|--------|--------|----------|
| `compact` | Low | Standard development |
| `minimal` | Very low | Large codebases, cost-sensitive |
| `full` | High | Debugging pipeline issues |

---

## Commands

| Command | Description |
|---------|------------|
| `flowai init` | Interactive wizard: pick AI provider, configure roles, scaffold editor configs |
| `flowai start` | Build knowledge graph → launch tmux pipeline (interactive by default) |
| `flowai start --headless` | Background mode for CI (no interactive prompts) |
| `flowai kill` | Stop the session |
| `flowai status` | Show session, config, skills, MCP health |
| `flowai run <phase>` | Run a single phase (`spec`, `plan`, `tasks`, `impl`, `review`) |
| `flowai graph build\|update\|lint\|query\|rollback` | Knowledge graph operations |
| `flowai skill add\|list\|remove` | Manage agent skills |
| `flowai role list\|edit\|set-prompt\|reset` | Manage role prompts |
| `flowai mcp add\|list\|remove` | Manage MCP servers |
| `flowai models list` | Show valid model IDs per tool |
| `flowai validate` | Check config against models catalog |
| `flowai update` | Self-update to latest version |
| `flowai version` | Print version |

---

## For Developers

Contributing to FlowAI:

```bash
git clone https://github.com/weprodev/FlowAI.git
cd FlowAI
make link         # symlinks fai/flowai to this workspace — edits are live
make test         # run the full test suite
make audit        # shellcheck + tests
make install      # production install (copy to /usr/local/flowai)
make uninstall    # remove from system
```

### Releasing

```bash
echo "0.2.0" > VERSION
git add VERSION && git commit -m "Bump to 0.2.0"
git tag v0.2.0 && git push origin main --tags
# → GitHub Actions: test on macOS + Linux + Windows → create Release
```

---

## Documentation

| Guide | What It Covers |
|-------|----------------|
| [Architecture](docs/ARCHITECTURE.md) | Pipeline, signals, plugins, event log, master monitoring, resolution chains |
| [Commands](docs/COMMANDS.md) | Every CLI command, environment variables, event log config |
| [Knowledge Graph](docs/GRAPH.md) | Build passes, community detection, versioning, chronicle, configuration |
| [Supported Tools](docs/TOOLS.md) | Tool plugin API, model catalog, config keys, vendor references |
---

## License

MIT — see [`LICENSE`](LICENSE).

<p align="center">
  Built with ❤️ by <a href="https://github.com/weprodev">WeProDev</a>
  <br /><br />
  <em>We build for growth, with growth in mind.<br />Join our community, contribute to the project, and let's shape the future of AI orchestration together!</em>
</p>
