<p align="center">
  <img src="logo.png" alt="FlowAI" width="420" />
</p>

<p align="center">
  <strong>Multi-agent terminal orchestration for software projects.</strong><br />
  Install once, run in any repository — per-project state under <code>.flowai/</code> and your existing <code>specs/</code> layout.
</p>

---

## Overview

FlowAI is a standalone **CLI** that coordinates **multiple AI agent tools** inside a **tmux** session. You configure which vendor CLIs power each role (master, planning, implementation, review, and so on); FlowAI manages **sessions**, **phases**, and **prompt wiring** without replacing those tools.

## Requirements

| Category           | Details                                                                                                                                          |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Runtime**        | `bash`, `jq`, `gum`, `tmux`                                                                                                                      |
| **Agent backends** | At least one [supported `tool` id](#supported-tools-and-editors) — install the vendor CLI separately; FlowAI only orchestrates                   |
| **Required**       | **`uv`** — used by `flowai init` to automatically bootstrap [GitHub Spec Kit](https://github.github.io/spec-kit/installation.html) (`.specify/`) |

## Installation

From a clone of this repository:

```bash
chmod +x install.sh
./install.sh
```

- **Install location:** `/usr/local/flowai`, with `flowai` linked into `/usr/local/bin`.
- **Development:** run `./bin/flowai` from the repo, or add `bin` to your `PATH` — no install required.

## Quick start (any project)

```bash
cd /path/to/your/repo
flowai init
flowai start
```

Sessions are named from a **hash of the repository path**, so two clones with the same folder name do not collide.

## Commands

| Command                               | Purpose                                                                  |
| ------------------------------------- | ------------------------------------------------------------------------ |
| `flowai init`                         | Creates `.flowai/` and bootstraps Spec Kit (`.specify/`) via `uvx`       |
| `flowai start`                        | Boots `tmux` session (pass `--headless` to skip prompt and run detached) |
| `flowai kill` / `flowai stop`         | End session (interactively prompts for confirmation if UI available)     |
| `flowai status`                       | List tmux windows if a session exists                                    |
| `flowai run`                          | Menu to select a phase to run (or pass directly, e.g. `flowai run spec`) |
| `flowai help`                         | Global commands and usage overview                                       |
| `flowai version` / `flowai --version` | Version from `VERSION` (use in bug reports)                              |

## Spec Kit (Specify)

FlowAI requires Spec Kit to handle upstream feature branch and issue automation. `flowai init` will automatically attempt to bootstrap it via `uv`:

```bash
uvx --from git+https://github.com/github/spec-kit.git specify init . --script sh
```

If it fails, install [Spec Kit](https://github.github.io/spec-kit/installation.html) manually.

## Testing and use cases

Behaviour is specified as **numbered, append-only use cases** under [`tests/usecases/`](tests/usecases/README.md) (`001-….md` — do not rewrite historical files to change intent; add new files instead).

Each file includes YAML frontmatter linked to automated tests. From the repository root:

```bash
make audit           # runs linters, test harness, and optional LLM review
```

**Optional LLM review:** `make audit` natively executes deterministic bash test assertions first. If they pass, it invokes **`gemini`** or **`claude`** to review intent vs log. Without an AI CLI, it provides the prompt text to paste elsewhere. Set `FLOWAI_SKIP_AI=1` for bash-only. Details: [`tests/agent/README.md`](tests/agent/README.md).

## License

MIT — see [`LICENSE`](LICENSE).
