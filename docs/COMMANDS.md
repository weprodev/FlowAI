# FlowAI Commands Reference

## Core Commands

| Command | Purpose |
|---------|---------|
| `fai` | Short alias for `flowai` — `bin/fai` symlinks to `bin/flowai`. |
| `flowai init` | Initialise `.flowai/` and bootstrap Spec Kit (`.specify/`) via `uvx`. |
| `flowai start [--headless]` | Boot the tmux session. `--headless` skips the attach prompt (CI-safe). |
| `flowai kill` / `flowai stop` | Terminate the session. |
| `flowai status` | List tmux windows for the current session. |
| `flowai run [<phase>]` | Run a pipeline phase. Omit `<phase>` for an interactive menu. |
| `flowai models list [<tool>\|all]` | Print valid model ids from `models-catalog.json`. Tools: `gemini`, `claude`, `cursor`, `copilot`, `all`. |
| `flowai validate` | Check `.flowai/config.json` model fields against `models-catalog.json`. Alias: `flowai config validate`. |
| `flowai mcp list` | Emit `.flowai/mcp.json` from configured MCP servers. |
| `flowai skill add \| remove \| list` | Manage skills assigned to pipeline roles. |
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
| Implement | `flowai run impl` | `tasks.ready` |
| Review | `flowai run review` | `impl.ready` |

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

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `FLOWAI_ALLOW_UNKNOWN_MODEL=1` | Skip catalog model validation at runtime. |
| `FLOWAI_SKIP_CONFIG_VALIDATE=1` | Skip start-time config validation only. |
| `FLOWAI_PHASE_TIMEOUT_SEC=N` | Hard timeout (seconds) for phase signal waits. `0` = unlimited (default). |
| `FLOWAI_TESTING=1` | Enable CI mode: bypass gum, auto-select dirs, skip dependency checks. |
| `FLOWAI_TEST_SKIP_AI=1` | Contract-test mode: phase scripts exit 0 before invoking AI. |
