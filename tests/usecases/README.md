# Application use cases (specifications)

This folder holds **immutable, migration-style specifications** for FlowAI behaviour. They align with **DDD / clean architecture** at the **application layer**: each file describes **one use case** (what a user does with the CLI and what must happen), not implementation details.

## Why `usecases` and not only “scenarios”?

| Term | Typical meaning | How we use it |
|------|------------------|---------------|
| **Use case** | Application service: a user goal with clear input/output (e.g. “invoke CLI without arguments”). | **One numbered `.md` file per use case** — stable contract with the business/product intent. |
| **Scenario** | Often a *path* or example inside a use case (Given/When/Then). | Written **inside** each file as structured sections. |

Naming the directory **`usecases`** keeps the mental model aligned with **ports & adapters**: the CLI is a driver; these documents are the **application** rules it must satisfy.

## Migration-style rules (like DB migrations)

1. **Append-only numbering** — Files are named `NNN-short-slug.md` (e.g. `001-cli-no-subcommand.md`).  
2. **Do not rewrite history** — Once merged, avoid editing a spec to *change* behaviour. If the product intent changes, add a **new** numbered file (e.g. `007-cli-…`) and optionally mark the old one **superseded** in a one-line note at the top.  
3. **Tests follow the spec** — Automated checks reference each use case via frontmatter (`automated_test`). If behaviour changes, add a new use case file and new test; keep old files for audit trail if needed.

This mirrors **migration files**: ordered, auditable, and safe for “what did we promise in Q2?” reviews.

## Layout

| File pattern | Role |
|--------------|------|
| `NNN-kebab-slug.md` | Full narrative + Given/When/Then + YAML frontmatter linking to code |
| `README.md` | This policy document |

## Link to automated tests

Each use case file includes YAML frontmatter:

```yaml
---
id: UC-CLI-001
automated_test: flowai_test_s_cli_001
---
```

- **`id`** — Stable product/test ID (prefix by area: `UC-CLI`, `UC-INIT`, …).  
- **`automated_test`** — Shell function in `tests/cases/*.sh` invoked from `tests/run.sh`.

**Verify bindings + run harness:**

```bash
make verify
```

**Optional — LLM review in the terminal** (needs `gemini` or `claude` on `PATH`):

```bash
make verify-ai
```

See `tests/agent/README.md` for the deterministic vs AI split.

## Related

- Executable harness: `tests/run.sh`, `tests/lib/harness.sh`  
- Agent orchestration: `tests/agent/`
