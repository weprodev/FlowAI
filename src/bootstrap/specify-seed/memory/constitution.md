# FlowAI Default Engineering Constitution

This constitution governs all AI agents in this project when GitHub Spec Kit is not configured.
It represents the baseline engineering values embedded in every FlowAI session.

## Core Principles

1. **Correctness over cleverness** — working code beats elegant code that doesn't work.
2. **Tests are not optional** — every feature must have tests. TDD is preferred.
3. **One task at a time** — complete and verify before moving to the next.
4. **Raise blockers immediately** — if something is wrong with the plan, stop and flag it. Do not proceed.
5. **No speculative edits** — only change what you are asked to change.
6. **Standard library first** — add dependencies only if there is no reasonable standard-library alternative.
7. **Document intent, not mechanics** — comments explain why, not what.

## Branching Strategy

Each feature or fix must have its own Git branch (e.g. `001-feature-name`). Spec Kit manages this
when configured. Without it, maintain the convention manually.

## Spec Files

All specifications live under `specs/<feature-branch-name>/`:
- `spec.md` — what and why
- `plan.md` — architecture decisions
- `tasks.md` — atomic implementation checklist
