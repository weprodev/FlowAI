# FlowAI

Standalone **multi-agent terminal orchestrator** for software projects. Install FlowAI once on your machine, then run it inside any repository — it keeps per-project state under `.flowai/` and uses your normal `specs/` feature folders.

## Requirements

- **bash**, **jq**, **gum**, **tmux**
- At least one **supported agent tool** (see table below) — install separately; FlowAI only orchestrates
- **uv** (optional, recommended) — used to bootstrap [GitHub Spec Kit](https://github.github.io/spec-kit/installation.html) (`.specify/`) when missing

## Supported tools & editors

Set `master.tool` and `roles.<role-id>.tool` in `.flowai/config.json` to one of these **`tool` ids** (implemented in `src/core/ai.sh`):

| `tool` id | Product | Where it runs | Behaviour in FlowAI |
|-----------|---------|----------------|---------------------|
| `gemini` | [Google Gemini CLI](https://github.com/google-gemini/gemini-cli) (`gemini`) | **Terminal** | Full CLI session in the tmux pane; non-interactive phases use `-m <model> -y` when appropriate. |
| `claude` | [Claude Code](https://github.com/anthropics/claude-code) (`claude`) | **Terminal** | Full CLI in the pane; pipeline phases use `--model` and `-p` for prompts; optional `--dangerously-skip-permissions` when `auto_approve` is true. |
| `cursor` | [Cursor CLI](https://cursor.com/) (`cursor`) | **Terminal + Cursor app** | FlowAI **stays in the terminal**: the combined prompt is printed in the pane (and you paste into Cursor Composer/Chat). FlowAI does not drive the GUI; the tmux session remains your orchestration surface. |

**Model strings** (`master.model`, `roles.*.model`) depend on each vendor’s CLI — use values that tool accepts (e.g. Gemini / Claude model names).

If you need another CLI later, extend `flowai_ai_run` in `src/core/ai.sh` and document the new `tool` id here.

## Install

From this repository:

```bash
chmod +x install.sh
./install.sh
```

This installs to `/usr/local/flowai` and links `flowai` into `/usr/local/bin`.

Development mode (no install): run `./bin/flowai` from a project using the absolute path or add `bin` to `PATH`.

## Quick start (in any project)

```bash
cd /path/to/your/repo
flowai init          # creates .flowai/config.json + specs/ (Spec Kit is optional — see below)
flowai init --with-specify   # optional: bootstrap GitHub Spec Kit via uvx (network)
flowai start         # tmux: master + plan/tasks/impl/review panes
flowai status        # list windows for this repo’s session
flowai kill          # tear down session
```

Session names are **hash-based per repository path**, so two clones with the same folder name do not collide.

## Commands

| Command | Purpose |
|--------|---------|
| `flowai init` | Create `.flowai/`, migrate legacy `.specify/memory/setup.json` if present, `mkdir specs` |
| `flowai init --with-specify` | After the above, attempt Spec Kit install via `uvx` (requires **uv**) |
| `flowai start` | Start tmux layout (dashboard or tabs from config) |
| `flowai start --headless` | Create the same session **without attaching** (CI; does not require **gum** on this step) |
| `flowai kill` / `flowai stop` | Kill this repo’s FlowAI session (`stop` is an alias) |
| `flowai status` | Show tmux windows if session exists |
| `flowai run <phase>` | Run one phase: `master`, `spec`, `plan`, `tasks`, `implement`, `review` |
| `flowai run --help` | Phases and usage for the `run` subcommand |
| `flowai version` / `flowai --version` | Installed version (from `VERSION`; use in bug reports) |

## Configuration

Edit `.flowai/config.json`:

- `master.tool` / `master.model` — interactive master pane (**`tool`** must be one of the ids in [Supported tools & editors](#supported-tools--editors))
- `pipeline` — maps phase → **role id** (e.g. `plan` → `team-lead`)
- `roles.<id>.tool` / `roles.<id>.model` — per-role CLI (hyphenated keys supported)

Override prompts by copying files from `$(dirname $(which flowai))/../src/roles/` into `.flowai/roles/` (e.g. `master.md`, `plan.md`).

## Spec Kit (Specify)

FlowAI does **not** run network installs by default. Use `flowai init --with-specify` to run:

```bash
uvx --from git+https://github.com/github/spec-kit.git specify init . --script sh
```

Or install [Spec Kit](https://github.github.io/spec-kit/installation.html) manually. FlowAI works without `.specify/`; you only need it for upstream `specs/` automation scripts some teams use.

## Testing & application use cases (DDD-friendly)

Product behaviour is specified as **immutable, numbered use cases** under [`tests/usecases/`](tests/usecases/README.md) (migration-style `001-….md` files — **append-only**; do not rewrite old specs to change intent).

Each file has YAML frontmatter linking to an automated test function. **Run in the terminal:**

```bash
make verify          # bindings (silent if OK) + bash harness — default gate
make verify-ai       # same as verify, then optional LLM review (Gemini or Claude CLI)
```

`make verify` no longer prints duplicate “binding OK” lines; wiring is checked inside `tests/run.sh`.

**AI in the terminal:** `make verify-ai` runs deterministic tests first, then invokes **`gemini`** or **`claude`** (whichever is on `PATH`) with a review prompt so an LLM reads your `tests/usecases/*.md` intent against the test log. No AI CLI? You get the same prompt text to paste into any client. Set `FLOWAI_SKIP_AI=1` to force bash-only. See [`tests/agent/README.md`](tests/agent/README.md).

## License

MIT — see `LICENSE`.
