# FlowAI Commands Reference

This is the comprehensive manual for operating the FlowAI terminal orchestrator.

## Core Commands

| Command                               | Purpose                                                                  |
| ------------------------------------- | ------------------------------------------------------------------------ |
| `flowai init`                         | Creates `.flowai/` and bootstraps Spec Kit (`.specify/`) via `uvx`       |
| `flowai start`                        | Boots `tmux` session (pass `--headless` to skip prompt and run detached) |
| `flowai kill` / `flowai stop`         | End session (interactively prompts for confirmation if UI available)     |
| `flowai status`                       | List tmux windows if a session exists                                    |
| `flowai run`                          | Menu to select a phase to run (or pass directly, e.g. `flowai run spec`) |
| `flowai help`                         | Global commands and usage overview                                       |
| `flowai version` / `flowai --version` | Version from `VERSION` (use in bug reports)                              |

---

## Technical Internals

### Interactive vs Headless Routing
Most `flowai` commands check standard input `[ -t 0 ]` to determine if they are running in an interactive terminal.
If executed under CI or `FLOWAI_TESTING=1`, `gum` menus and confirmations are automatically safely bypassed to prevent deadlocking.

### Spec Kit (Specify) Integration
FlowAI requires Spec Kit to handle upstream feature branch and issue automation. `flowai init` will automatically attempt to bootstrap it via `uv`:

```bash
uvx --from git+https://github.com/github/spec-kit.git specify init . --script sh
```

If it fails over the network or `uv` is unavailable, you can explicitly configure Spec Kit [manually](https://github.github.io/spec-kit/installation.html).
