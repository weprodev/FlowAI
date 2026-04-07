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
| `flowai models list` [claude\|gemini\|cursor\|all] | Print valid model ids from repo-root `models-catalog.json` |
| `flowai config validate` | Check `default_model`, `claude_default_model`, `master`, and `roles.*` against the catalog |

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

### Configuration (models and tools)

`.flowai/config.json` drives which CLI and model each phase uses:

| Key | Purpose |
|-----|---------|
| `master.tool` / `master.model` | Master (and spec) phase |
| `roles.<id>.tool` / `roles.<id>.model` | Pipeline roles (plan, tasks, impl, review map via `pipeline`) |
| `default_model` | Default Gemini model when a role omits `model` |
| `claude_default_model` | Default Claude Code model when a role omits `model` or uses an invalid OpenAI-style id with `tool: "claude"` |

**Before `flowai start`:** model fields are validated against **`models-catalog.json`** (unless `FLOWAI_TESTING=1`, `FLOWAI_SKIP_CONFIG_VALIDATE=1`, or `FLOWAI_ALLOW_UNKNOWN_MODEL=1`). Run **`flowai config validate`** after editing `.flowai/config.json`.

At **run time**, invalid Gemini/Claude ids are still corrected in `flowai_ai_run` with a warning (same escape hatch: `FLOWAI_ALLOW_UNKNOWN_MODEL=1`). See [Supported AI Tools](TOOLS.md).
