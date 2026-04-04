---
id: UC-CLI-001
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_001
status: implemented
---

# UC-CLI-001 — Invoke `flowai` with no subcommand

## Intent

The user must always see **how to use** the tool when they run the entry binary without a valid command. This is the default “empty invocation” path.

## Preconditions (Given)

- FlowAI is installed or invoked via `bin/flowai` with `FLOWAI_HOME` resolved.
- Current working directory is arbitrary (no project init required).

## Action (When)

The user runs:

```bash
flowai
```

(with no further arguments)

## Expected outcome (Then)

- **Exit code:** `1` (failure — a subcommand is required).
- **Standard output** must include both:
  - the word `Usage` (or equivalent usage banner), and  
  - the product name `FlowAI`.
- No silent exit: the user always gets orientation.

## Automated checks

Implemented by `flowai_test_s_cli_001` in `tests/suites/cli_entrypoint.sh`.
