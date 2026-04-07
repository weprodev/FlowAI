# FlowAI Supported Tools and Editors

Set `master.tool` and `roles.<role-id>.tool` in `.flowai/config.json` to one of these **`tool` ids** (implemented in `src/core/ai.sh`):

| `tool` id | Product | Where it runs | Behaviour in FlowAI |
|-----------|---------|---------------|----------------------|
| `gemini` | [Google Gemini CLI](https://github.com/google-gemini/gemini-cli) (`gemini`) | Terminal | Full CLI session in the tmux pane; non-interactive phases use `-m <model> -y` when appropriate. |
| `claude` | [Claude Code](https://github.com/anthropics/claude-code) (`claude`) | Terminal | Full CLI in the pane; pipeline phases use `--model` and `-p` for prompts; optional `--dangerously-skip-permissions` when `auto_approve` is true. |
| `cursor` | [Cursor](https://cursor.com/) (app + [CLI](https://cursor.com/docs/cli/overview)) | Terminal + Cursor app | FlowAI **stays in the terminal**: the combined prompt is printed in the pane (paste into Composer/Agent as needed). Cursor itself can use **many** provider models (Anthropic, OpenAI, Google, etc.); see [Cursor models](https://cursor.com/docs/models). The catalog’s `cursor` entries are **labels you can mirror in config** for documentation — FlowAI does not pass `--model` for this tool. |

## Models and `.flowai/config.json`

### Bundled catalog (source of truth)

FlowAI ships **`models-catalog.json`** at the **repository root** (copied next to `bin/` and `src/` when you install). For each `tool` it lists **valid model ids**, **`default_id`**, optional **`note`**, and links to vendor docs. Run:

```bash
flowai models list
flowai models list gemini
flowai models list claude
flowai models list cursor
```

`flowai init` copies **`default_id`** from that file into `default_model`, `claude_default_model`, and each role’s `model` for new projects. After manual edits, run **`flowai config validate`**; **`flowai start`** also runs the same checks (fail-fast) in normal use.

### Config keys

- **`default_model`** — Gemini default when a role omits `model` or when resolving Gemini phases.
- **`claude_default_model`** — Claude default for the same cases.
- **`master.model`** / **`roles.<role-id>.model`** — Must be an **`id`** listed under the matching tool in the catalog.

At runtime, if the configured model is **not** in the catalog for that tool, FlowAI logs a warning and substitutes the catalog **`default_id`**. To pass through an id before you update the JSON (e.g. vendor shipped a new name), set **`FLOWAI_ALLOW_UNKNOWN_MODEL=1`**.

OpenAI-style ids with **`tool: "claude"`** (e.g. `gpt-4o`) are still rejected and replaced with **`claude_default_model`**.

### Vendor references

The catalog is curated from:

- [Claude Code CLI reference](https://code.claude.com/docs/en/cli-reference) (`--model`)
- [Gemini CLI models](https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/model.md)

Use `/model` inside Claude Code or Gemini CLI for live options tied to your account.

**Extending:** Add ids to `models-catalog.json`, run `flowai models list` to verify, and extend `flowai_ai_run` in `src/core/ai.sh` if you add a new `tool` id.
