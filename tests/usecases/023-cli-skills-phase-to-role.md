---
id: UC-CLI-023
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_023
status: implemented
---

# UC-CLI-023 — Skills resolve pipeline phase to role

## Intent

Skill assignments in `config.json` are keyed by **role** (e.g. `team-lead`, `backend-engineer`), while phase scripts pass **phase** names (`plan`, `impl`, …). FlowAI must map phase → pipeline role before resolving skills.

## Preconditions (Given)

- `jq` is installed.
- A fresh project created with `flowai init` (default pipeline and skills).

## Action (When)

Automated test sources `src/core/skills.sh` and asserts `flowai_skills_effective_role_for_phase` and `flowai_skills_list_for_role`.

## Expected outcome (Then)

- Phase `plan` maps to role `team-lead`.
- Phase `impl` maps to role `backend-engineer`.
- `team-lead` includes `writing-plans` from defaults.

## Automated checks

`flowai_test_s_cli_023` in `tests/suites/lifecycle_happy.sh`.
