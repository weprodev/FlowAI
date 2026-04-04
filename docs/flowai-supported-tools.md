# FlowAI Supported Tools and Editors

Set `master.tool` and `roles.<role-id>.tool` in `.flowai/config.json` to one of these **`tool` ids** (implemented in `src/core/ai.sh`):

| `tool` id | Product | Where it runs | Behaviour in FlowAI |
|-----------|---------|---------------|----------------------|
| `gemini` | [Google Gemini CLI](https://github.com/google-gemini/gemini-cli) (`gemini`) | Terminal | Full CLI session in the tmux pane; non-interactive phases use `-m <model> -y` when appropriate. |
| `claude` | [Claude Code](https://github.com/anthropics/claude-code) (`claude`) | Terminal | Full CLI in the pane; pipeline phases use `--model` and `-p` for prompts; optional `--dangerously-skip-permissions` when `auto_approve` is true. |
| `cursor` | [Cursor CLI](https://cursor.com/) (`cursor`) | Terminal + Cursor app | FlowAI **stays in the terminal**: the combined prompt is printed in the pane (paste into Cursor Composer/Chat as needed). FlowAI does not drive the GUI; tmux remains the orchestration surface. |

**Models:** `master.model` and `roles.*.model` must be values accepted by each vendor’s CLI (for example Gemini or Claude model names).

**Extending:** To add another CLI, extend `flowai_ai_run` in `src/core/ai.sh` and document the new `tool` id in this file.
