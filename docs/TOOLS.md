# FlowAI Supported Tools

Set `master.tool` and `roles.<role-id>.tool` in `.flowai/config.json` to one of these **`tool` ids** (each implemented as a plugin in `src/tools/<name>.sh`):

| `tool` id | Product | Where it runs | FlowAI behaviour |
|-----------|---------|---------------|-----------------|
| `gemini`  | [Google Gemini CLI](https://github.com/google-gemini/gemini-cli) | Terminal | Full CLI session in the tmux pane; non-interactive phases add `-m <model> -y`. |
| `claude`  | [Claude Code](https://github.com/anthropics/claude-code) | Terminal | Full CLI in the pane; pipeline phases use `--model` and `-p`; `--dangerously-skip-permissions` when `auto_approve: true`. Optional MCP config via `--mcp-config` if `.flowai/mcp.json` exists. |
| `cursor`  | [Cursor](https://cursor.com/) | Terminal + Cursor app | FlowAI prints the enriched prompt in the terminal for manual paste into Composer/Agent. Cursor routes internally to many providers; see [Cursor models](https://cursor.com/docs/models). |
| `copilot` | [GitHub Copilot Chat](https://docs.github.com/en/copilot) | Terminal + Copilot Chat | FlowAI prints the prompt for paste into Copilot Chat (no headless CLI available). Model routing is managed by GitHub. |

**Adding a new tool:** create `src/tools/<name>.sh` defining three functions, then add the `tools.<name>` entry to `models-catalog.json`. No other files need to change.

| Function | Purpose |
|----------|---------|
| `flowai_tool_<name>_print_models()` | Used by `flowai models list` |
| `flowai_tool_<name>_run(model, auto_approve, run_interactive, sys_prompt)` | Phase dispatcher — runs full AI session |
| `flowai_tool_<name>_run_oneshot(model, prompt_file)` | Non-interactive single-prompt for knowledge graph semantic extraction |

Tools without a headless CLI (Cursor, Copilot) should return empty JSON from `_run_oneshot`:
```bash
printf '{"nodes":[],"edges":[],"insights":[]}'
```

---

## Models and `.flowai/config.json`

### Bundled catalog

FlowAI ships **`models-catalog.json`** at the repository root. For each tool it lists valid model ids, a `default_id`, optional notes, and links to vendor docs. Inspect with:

```bash
flowai models list          # all tools
flowai models list gemini
flowai models list claude
flowai models list cursor
flowai models list copilot
```

`flowai init` copies each tool's `default_id` from the catalog into the project config. After editing, run **`flowai validate`**. `flowai start` also validates on launch.

### Config keys

| Key | Purpose |
|-----|---------|
| `tool_defaults.<tool>.model` | Per-tool model override (any tool, new generic format) |
| `default_model` | Gemini model override (legacy; still respected) |
| `claude_default_model` | Claude model override (legacy; still respected) |
| `master.model` / `roles.<id>.model` | Per-phase model (must be in catalog for gemini/claude) |

At runtime, model ids not found in the catalog are replaced with `default_id` and a warning is logged. Use **`FLOWAI_ALLOW_UNKNOWN_MODEL=1`** to pass any id through unchecked.

OpenAI-style ids (e.g. `gpt-4o`) with `tool: "claude"` are rejected and replaced with the Claude default.

### Vendor references

- [Claude Code CLI reference](https://code.claude.com/docs/en/cli-reference) — `--model` values
- [Gemini CLI models](https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/model.md)
- [Cursor models](https://cursor.com/docs/models)
- [GitHub Copilot model availability](https://docs.github.com/en/copilot/github-copilot-in-the-cli)
