# Test agent — deterministic vs AI layer

## Why two layers?

| Layer | Command | What it proves |
|-------|---------|----------------|
| **Deterministic** | `make verify` / `bash tests/run.sh` | Exact exit codes and strings — fast, CI-safe, no API keys. Includes **silent** use case ↔ test wiring. |
| **AI review (optional)** | `make verify-ai` | After green tests, **Gemini CLI** or **Claude Code** reads `tests/agent/prompts/llm-smoke-review.md` plus the test log and **comments** on whether the markdown use cases still match reality / gaps. This is judgement, not a second test runner. |

Bash cannot “understand” product intent; an LLM can sanity-check docs vs behaviour. That is the extra value over `make verify` alone.

## Commands

```bash
make verify              # default — bindings + harness only
make verify-usecases     # wiring check only (verbose count)
make verify-ai           # verify + LLM review (or paste prompt if no CLI)
bash tests/agent/run-ai-smoke.sh --interactive   # hand terminal to gemini for a longer session
```

## Environment

| Variable | Effect |
|----------|--------|
| `FLOWAI_SKIP_AI=1` | Used by `run-ai-smoke.sh`: stop after deterministic tests (CI). |
| `FLOWAI_AI_MODEL=…` | Passed to `gemini -m` / `claude --model` when set. |

## CI recommendation

- **Required:** `make verify` (or `make test`).
- **Optional nightly:** `make verify-ai` with secrets for Gemini/Claude — allow soft-fail if quota errors.

## “Famous” AI CLIs

FlowAI does not vendor a model. It shells out to whatever you install:

- **Google Gemini CLI** (`gemini`)
- **Anthropic Claude Code** (`claude`)

Cursor Composer is IDE-based — not scripted here; use the printed prompt from `verify-ai` when no CLI is found.
