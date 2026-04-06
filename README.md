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

**Universal Install (Recommended):**

Execute via curl to securely download and install without cloning manually:

```bash
curl -fsSL https://raw.githubusercontent.com/WeProDev/FlowAI/main/install.sh | bash
```

Alternatively, if you cloned the repository, execute:

```bash
make install
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

## 📚 Documentation Architecture

FlowAI is built for scale. To fully harness its capabilities, refer to our single-source-of-truth documentation hubs:

| Guide | Description |
|-------|-------------|
| 🧭 **[System Architecture](docs/ARCHITECTURE.md)** | The roadmap for our orchestration loop, DAG scaling, and forthcoming **MCP / VCS Integrations**. |
| 🎛️ **[Commands Reference](docs/COMMANDS.md)** | Granular manuals for the CLI footprint and Spec Kit configuration. |
| 🤖 **[Supported AI Tools](docs/TOOLS.md)** | Matrices detailing our vendor API integrations (Gemini, Claude, Cursor). |
| 🧪 **[Testing Framework](tests/usecases/README.md)** | The exact Behavior-Driven Development parameters and YAML validation suite mapping. |

---

## Testing and Use Cases

FlowAI behaviour is verified natively. From the repository root:

```bash
make audit           # runs linters, deterministic harness, and optional LLM context review
```

## License

MIT — see [`LICENSE`](LICENSE).
