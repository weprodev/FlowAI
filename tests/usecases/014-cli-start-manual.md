---
id: UC-CLI-014
layer: application
bounded_context: cli
automated_test: flowai_test_s_cli_014
status: implemented
---

# UC-CLI-014 — Start session (`flowai start`)

## Intent

**Interactive (default):** `flowai start` creates or attaches a **tmux** session and, after layout setup, **attaches** so the user can work. **gum** is required for phase approval menus when running phases later in those panes.

**Headless (`--headless` or `FLOWAI_START_HEADLESS=1`):** Same tmux layout and launchers are created, but the command **exits without attaching** (no TTY). **gum** is not required for this entry path because nothing is attached to interactive approval UIs. Use this for **deterministic smoke tests** and headless environments.

## Preconditions (Given)

- **Interactive:** `tmux`, `jq`, `gum`, and `flowai init` in the repo.
- **Headless:** `tmux`, `jq`, `flowai init`; gum optional.

## Action (When)

Interactive:

```bash
flowai start
```

Headless (CI / automation):

```bash
flowai start --headless
```

## Expected outcome (Then)

- **Exit code:** `0`.
- A tmux session exists for this repository’s stable session name (see `src/core/session.sh`).
- Interactive: user is attached (or switched) to the session.
- Headless: output includes a **headless** line and the process does **not** block on attach.

## Automated checks

`flowai_test_s_cli_014` runs `init` in a temp dir, then `flowai start --headless`, asserts exit **0**, output mentions **Headless**, and **`tmux has-session`** for the computed session name; session is **killed** in a cleanup trap.
