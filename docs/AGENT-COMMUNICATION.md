# Agent Communication & Phase Coordination

FlowAI orchestrates multiple AI agents in a tmux session. Each agent runs in
its own pane, working on a specific pipeline phase. This document describes how
agents communicate, pass data, and coordinate — and why the design is agnostic
of the specific AI tool, role, or skill assigned to each phase.

---

## Design Principles

1. **Phase scripts own the contract.** Every inter-agent handoff is managed by
   bash scripts in `src/phases/`. The role files (`src/roles/`) describe _what_
   the agent is; the phase scripts describe _when_ it starts, _what_ it reads,
   _where_ it writes, and _how_ it signals completion.

2. **Tool-agnostic.** Whether a phase runs Gemini, Claude, Cursor, or Copilot,
   the coordination logic is identical. The tool plugin (`src/tools/*.sh`) is
   only responsible for launching the AI CLI — it never touches signals, events,
   or artifact paths.

3. **Role-agnostic.** A user can create any custom role (e.g., `mobile-engineer.md`)
   and assign it to a phase in `config.json`. The pipeline will work without
   changes because the coordination preamble is injected at the prompt composition
   layer (`src/core/skills.sh`), not inside each role file.

4. **Skill-agnostic.** Skills are appended to prompts but play no part in
   signal coordination or data flow.

---

## Pipeline Overview

```
                ┌──────────┐
                │  Master  │ ← interactive, user-facing
                │ (spec)   │
                └────┬─────┘
                     │ spec.ready
                     ▼
                ┌──────────┐
                │   Plan   │ ← oneshot, auto-exits
                └────┬─────┘
                     │ plan.ready
                     ▼
                ┌──────────┐
                │  Tasks   │
                └────┬─────┘
                     │ tasks.ready
                     ▼
                ┌──────────┐
                │   Impl   │
                └────┬─────┘
                     │ impl.ready
                     ▼
                ┌──────────┐
                │  Review  │
                └──────────┘
```

---

## Communication Mechanisms

### 1. Signal Files (`.flowai/signals/*.ready`)

Signals are the primary inter-phase synchronisation mechanism. Each downstream
phase blocks on its upstream signal before starting.

| Signal File   | Created By                                                   | Consumed By     |
| ------------- | ------------------------------------------------------------ | --------------- |
| `spec.ready`  | Master phase (after human approves `spec.md`)                | Plan phase      |
| `plan.ready`  | Plan phase (after human approves `plan.md`)                  | Tasks phase     |
| `tasks.ready` | Tasks phase (after human approves `tasks.md`)                | Implement phase |
| `impl.ready`  | Implement phase (after human approves `tasks.md` checkboxes) | Review phase    |

**Rejection & revision signals:**

| Signal File              | Created By              | Consumed By              |
| ------------------------ | ----------------------- | ------------------------ |
| `<phase>.reject`         | `verify_artifact` on reject | Informational (cleaned up on revision) |
| `<phase>.revision.ready` | **Human operator** (manual touch) | The rejected phase (unblocks retry) |

> **Important:** After a downstream phase is rejected, `flowai_phase_run_loop`
> waits for `<phase>.revision.ready` before retrying. The Master Agent provides
> guidance but does **not** create this signal automatically. The human operator
> must explicitly signal that the revision is ready:
>
> ```bash
> touch .flowai/signals/plan.revision.ready
> ```

**How it works:**

```bash
# Downstream phase blocks here until the signal exists:
flowai_phase_wait_for "spec" "Plan Phase"
#   → polls for .flowai/signals/spec.ready every 2 seconds

# Signal is created by flowai_phase_verify_artifact() when human approves:
#   → touch "$SIGNALS_DIR/${signal}.ready"
```

Signals are **always** created by `flowai_phase_verify_artifact()` in
`src/core/phase.sh`. No phase script, role file, or tool plugin creates
signals directly.

### 2. Artifact Files (`specs/<branch>/*.md`)

Phases communicate data by writing to and reading from shared artifact files in
the feature directory.

| Artifact   | Written By | Read By                   |
| ---------- | ---------- | ------------------------- |
| `spec.md`  | Master     | Plan, Tasks, Impl, Review |
| `plan.md`  | Plan       | Tasks, Impl, Review       |
| `tasks.md` | Tasks      | Impl, Review              |

Each phase script's `DIRECTIVE` variable tells the AI agent:

- **CONTEXT** — which upstream artifacts to read (absolute paths)
- **OUTPUT FILE** — where to write the output (absolute path)

Example from `plan.sh`:

```bash
DIRECTIVE="IMPORTANT PIPELINE DIRECTIVE:
You are assigned to Phase: Plan (Architecture).
Your WORKING DIRECTORY is: $PWD

CONTEXT — read the following upstream artifact before starting:
  $FEATURE_DIR/spec.md

OUTPUT FILE — you MUST write your artifact to this exact path:
  $FEATURE_DIR/plan.md"
```

### 3. Event Log (`.flowai/events.jsonl`)

A shared, append-only JSONL file that gives all agents visibility into pipeline
activity. Each event has the format:

```json
{ "ts": "2026-04-12T06:30:00Z", "phase": "plan", "event": "started", "detail": "Beginning AI run" }
```

**Event types:**

| Event               | Meaning                                       |
| ------------------- | --------------------------------------------- |
| `waiting`           | Phase is blocked, waiting for upstream signal |
| `started`           | Phase AI run has begun                        |
| `artifact_produced` | Phase output file written                     |
| `approved`          | Human approved the artifact                   |
| `rejected`          | Human rejected the artifact                   |
| `progress`          | Implementation progress (e.g., "3/7 tasks")   |
| `phase_complete`    | Phase fully done (approved + signal fired)    |
| `pipeline_complete` | All phases done                               |

The event log is injected into every agent's prompt as `[PIPELINE EVENT LOG]`
so agents can understand what other agents have done.

### 4. Rejection Context File

When the Review phase finds issues, it writes structured feedback to:

```
.flowai/signals/impl.rejection_context
```

On re-run, the Implement phase reads this file and focuses only on the
failing items instead of re-implementing everything.

---

## Phase Lifecycle (How Each Phase Runs)

### Downstream Phases (plan, tasks, impl, review)

All downstream phases follow the same lifecycle via `flowai_phase_run_loop()`:

```
┌─────────────────────────────────────────────────────┐
│ 1. Wait for upstream signal                         │
│    flowai_phase_wait_for("spec", "Plan Phase")       │
│                                                     │
│ 2. Resolve feature directory                        │
│    flowai_phase_resolve_feature_dir()                │
│                                                     │
│ 3. Resolve role prompt (5-tier chain)               │
│    flowai_phase_resolve_role_prompt("plan")          │
│                                                     │
│ 4. Compose DIRECTIVE with absolute paths            │
│                                                     │
│ 5. Write enriched prompt file                        │
│    flowai_phase_write_prompt("plan", ...)            │
│                                                     │
│ 6. Enter run loop:                                  │
│    ┌───────────────────────────────────────────┐    │
│    │ a) AI run (dispatched to tool plugin)     │    │
│    │ b) Verify artifact exists                 │    │
│    │ c) Human approval gate                    │    │
│    │    → Approve: emit signal, break          │    │
│    │    → Retry:   loop back to (a)            │    │
│    │    → Reject:  wait for revision signal    │    │
│    └───────────────────────────────────────────┘    │
│                                                     │
│ 7. Emit phase_complete event                        │
└─────────────────────────────────────────────────────┘
```

### Master Phase

The Master phase is the only interactive phase. It follows a similar lifecycle
but uses `flowai_ai_run` in interactive mode (the AI stays in a REPL):

```
┌─────────────────────────────────────────────────────┐
│ 1. Resolve role prompt (5-tier chain)               │
│ 2. Resolve feature directory (or create from branch)│
│ 3. Compose DIRECTIVE with absolute paths            │
│ 4. Run interactive AI session                       │
│                                                     │
│ 5. Artifact verification loop:                       │
│    ┌───────────────────────────────────────────┐    │
│    │ a) Verify spec.md exists                  │    │
│    │ b) Human approval gate                    │    │
│    │    → Approve: emit spec.ready, break      │    │
│    │    → Retry/Reject: re-enter interactive   │    │
│    └───────────────────────────────────────────┘    │
│                                                     │
│ 6. Enter Phase 2: Pipeline Monitor                  │
│    → Polls event log for rejections                 │
│    → Re-invokes AI with rejection context           │
│    → Exits when review phase completes              │
└─────────────────────────────────────────────────────┘
```

> [!WARNING]
> **`flowai run spec` vs Master:** Both can produce `spec.md` and emit
> `spec.ready`. Do not run `flowai run spec` concurrently with a `fai start`
> session — they will race on the same artifact and approval gate.

---

## Prompt Composition Stack

Every agent's prompt is assembled by `flowai_skills_build_prompt()` in
`src/core/skills.sh`. The composition order is:

```
1. Role file content        (e.g., src/roles/backend-engineer.md)
2. Pipeline Coordination    (auto-injected, role-agnostic preamble)
3. Project Constitution     (.specify/memory/constitution.md)
4. Knowledge Graph context  (if enabled)
5. Pipeline Event Log       (recent events from events.jsonl)
6. Assigned Skills          (SKILL.md files for the role)
```

Layer 2 (Pipeline Coordination) is the key to agnosticism — it is injected
into **every** agent prompt regardless of role, skill, or tool. It tells the
agent:

- The phase script handles signal waiting — the agent does not check signals
- All artifact paths are in the PIPELINE DIRECTIVE section
- The orchestrator handles artifact verification and approval

This means a user can create a brand new role file (e.g., `ios-engineer.md`)
with zero knowledge of FlowAI internals and it will work correctly in the
pipeline.

---

## Adding a New Phase

1. Add the phase name to `FLOWAI_PIPELINE_PHASES` in `src/core/phases.sh`
2. Create `src/phases/<name>.sh` following the standard lifecycle:
   ```bash
   flowai_phase_wait_for "<upstream_signal>" "<My Phase>"
   FEATURE_DIR="$(flowai_phase_resolve_feature_dir)"
   ROLE_FILE="$(flowai_phase_resolve_role_prompt "<name>")"
   DIRECTIVE="..."
   INJECTED_PROMPT="$(flowai_phase_write_prompt "<name>" "$ROLE_FILE" "$DIRECTIVE")"
   flowai_phase_run_loop "<name>" "$INJECTED_PROMPT" "$artifact" "$label" "$signal"
   ```
3. That's it — `start.sh`, `eventlog.sh`, and `bin/flowai` all read from the
   canonical phase list automatically.

## Adding a New Tool

1. Create `src/tools/<name>.sh` with the required plugin API:
   - `flowai_tool_<name>_run(model, auto_approve, run_interactive, sys_prompt)`
   - `flowai_tool_<name>_print_models()`
   - `flowai_tool_<name>_run_oneshot(model, prompt_file)`
2. Add the tool to `models-catalog.json`
3. That's it — `ai.sh` discovers plugins dynamically via `src/tools/*.sh` glob.

## Adding a New Role

1. Create a markdown file (e.g., `src/roles/ios-engineer.md`) describing the
   agent's domain responsibilities.
2. Do NOT include pipeline coordination, signal paths, or directive references —
   those are injected automatically by the prompt composition layer.
3. Assign the role to a phase in `.flowai/config.json`:
   ```json
   { "pipeline": { "impl": "ios-engineer" } }
   ```
