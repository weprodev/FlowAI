#!/usr/bin/env bash
# FlowAI test suite — phase signal coordination
# Tests the signal protocol, role resolution, and prompt composition.
# For behavioral regressions (event JSON, verdict logic, async signals), see
# orchestration_contracts.sh — prefer adding there when a bug escaped CI.
# shellcheck shell=bash
#
# Temp projects: env FLOWAI_DIR=… bash -s <<'EOS' … EOS (avoids SC2030/SC2031 on export-in-subshell).

# shellcheck source=../../src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"

# ─── SIG-001: phase_wait_for returns immediately if signal exists ────────────
flowai_test_s_sig_001() {
  local id="SIG-001"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai/signals"
  printf '{"master":{"tool":"gemini","model":"gemini-2.5-pro"},"pipeline":{"plan":"team-lead"}}' > "$scratch/.flowai/config.json"
  touch "$scratch/.flowai/signals/spec.ready"
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
# shellcheck source=../../src/core/phase.sh
source "$FLOWAI_HOME/src/core/phase.sh"
flowai_phase_wait_for "spec" "test-phase"
EOS
  local rc=$?
  if [[ "$rc" -eq 0 ]]; then
    flowai_test_pass "$id" "phase_wait_for returns 0 when signal exists"
  else
    printf 'FAIL %s: expected rc=0, got %s\n' "$id" "$rc" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── SIG-002: phase_wait_for times out correctly ────────────────────────────
flowai_test_s_sig_002() {
  local id="SIG-002"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai/signals"
  printf '{"master":{"tool":"gemini","model":"gemini-2.5-pro"}}' > "$scratch/.flowai/config.json"
  local rc=0
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" FLOWAI_PHASE_TIMEOUT_SEC=2 \
    bash -s 2>/dev/null <<'EOS' || rc=$?
# shellcheck source=../../src/core/phase.sh
source "$FLOWAI_HOME/src/core/phase.sh"
flowai_phase_wait_for "nonexistent" "test-phase"
EOS
  if [[ "$rc" -ne 0 ]]; then
    flowai_test_pass "$id" "phase_wait_for times out correctly"
  else
    printf 'FAIL %s: expected non-zero rc on timeout, got %s\n' "$id" "$rc" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── SIG-003: Role prompt resolution finds bundled role ──────────────────────
flowai_test_s_sig_003() {
  local id="SIG-003"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  printf '{"master":{"tool":"gemini","model":"gemini-2.5-pro"},"pipeline":{"plan":"team-lead"}}' > "$scratch/.flowai/config.json"
  local result
  result="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
# shellcheck source=../../src/core/phase.sh
source "$FLOWAI_HOME/src/core/phase.sh"
flowai_phase_resolve_role_prompt "plan"
EOS
)"
  if [[ "$result" == *"src/roles/team-lead.md" ]]; then
    flowai_test_pass "$id" "Role resolution finds bundled team-lead role"
  else
    printf 'FAIL %s: expected team-lead.md, got %s\n' "$id" "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── SIG-004: Role prompt resolution uses phase override when present ────────
flowai_test_s_sig_004() {
  local id="SIG-004"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai/roles"
  printf '{"master":{"tool":"gemini","model":"gemini-2.5-pro"},"pipeline":{"plan":"team-lead"}}' > "$scratch/.flowai/config.json"
  printf '# Custom plan role\n' > "$scratch/.flowai/roles/plan.md"
  local result
  result="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<'EOS'
# shellcheck source=../../src/core/phase.sh
source "$FLOWAI_HOME/src/core/phase.sh"
flowai_phase_resolve_role_prompt "plan"
EOS
)"
  if [[ "$result" == "$scratch/.flowai/roles/plan.md" ]]; then
    flowai_test_pass "$id" "Role resolution uses phase-level override"
  else
    printf 'FAIL %s: expected phase override, got %s\n' "$id" "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── SIG-005: Prompt composition includes role + directive ───────────────────
flowai_test_s_sig_005() {
  local id="SIG-005"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai/launch"
  printf '{"master":{"tool":"gemini","model":"gemini-2.5-pro"}}' > "$scratch/.flowai/config.json"
  local role_file="$FLOWAI_HOME/src/roles/backend-engineer.md"
  local prompt_file content
  prompt_file="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<EOF
# shellcheck source=../../src/core/phase.sh
source "\$FLOWAI_HOME/src/core/phase.sh"
flowai_phase_write_prompt "test" "$role_file" "TEST DIRECTIVE"
EOF
)"
  if [[ -f "$prompt_file" ]]; then
    content="$(cat "$prompt_file")"
    if [[ "$content" == *"TEST DIRECTIVE"* ]]; then
      flowai_test_pass "$id" "Prompt composition includes directive"
    else
      printf 'FAIL %s: prompt missing directive\n' "$id" >&2
      FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    fi
  else
    printf 'FAIL %s: prompt file not created\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── SIG-006: phase_wait_for fast path does not emit waiting event ───────────
flowai_test_s_sig_006() {
  local id="SIG-006"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai/signals"
  printf '{"master":{"tool":"gemini","model":"gemini-2.5-pro"}}' > "$scratch/.flowai/config.json"
  touch "$scratch/.flowai/signals/spec.ready"
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s 2>/dev/null <<'EOS'
# shellcheck source=../../src/core/phase.sh
source "$FLOWAI_HOME/src/core/phase.sh"
flowai_phase_wait_for "spec" "test-phase"
EOS
  # Contract: when signal is already ready, wait_for returns immediately
  # without emitting a "waiting" event. Either no events file exists, or
  # it must not contain a "waiting" event for our phase.
  if [[ -f "$scratch/.flowai/events.jsonl" ]] && \
     grep -q '"event":"waiting"' "$scratch/.flowai/events.jsonl" 2>/dev/null; then
    printf 'FAIL %s: waiting event should not be emitted on fast path\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  else
    flowai_test_pass "$id" "No event emitted when signal already ready (fast path)"
  fi
  rm -rf "$scratch"
}

# ─── SIG-007: PIPELINE COORDINATION block is always present in composed prompt ─
# This is the architectural invariant: every agent sees the pipeline rules
# regardless of role, skill, or tool. This test calls flowai_skills_build_prompt
# directly and asserts [PIPELINE COORDINATION] is present in the output.
flowai_test_s_sig_007() {
  local id="SIG-007"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai/launch"
  printf '{"master":{"tool":"gemini","model":"gemini-2.5-pro"}}' > "$scratch/.flowai/config.json"

  # Create a minimal role+directive prompt file (simulates flowai_phase_write_prompt output)
  local prompt_file="$scratch/.flowai/launch/test_prompt.md"
  printf '# Minimal Role\nYou are a test agent.\n\nTEST DIRECTIVE\n' > "$prompt_file"

  # Call flowai_skills_build_prompt and capture the full composed prompt
  local composed
  composed="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" PWD="$scratch" bash -s <<'EOS'
# shellcheck source=../../src/core/config.sh
source "$FLOWAI_HOME/src/core/config.sh"
# shellcheck source=../../src/core/skills.sh
source "$FLOWAI_HOME/src/core/skills.sh"
# shellcheck source=../../src/core/eventlog.sh
source "$FLOWAI_HOME/src/core/eventlog.sh"
# shellcheck source=../../src/core/graph.sh
source "$FLOWAI_HOME/src/core/graph.sh" 2>/dev/null || true
flowai_skills_build_prompt "plan" "$FLOWAI_DIR/launch/test_prompt.md"
EOS
)"

  if [[ "$composed" == *"PIPELINE COORDINATION"* ]]; then
    flowai_test_pass "$id" "PIPELINE COORDINATION block injected in composed prompt"
  else
    printf 'FAIL %s: [PIPELINE COORDINATION] block missing from composed prompt\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── SIG-008: master.sh requires user_approved marker before spec.ready ──────
# Spec approval must be explicit (marker file), NOT auto on spec.md existence.
flowai_test_s_sig_008() {
  local id="SIG-008"
  local plugin="$FLOWAI_HOME/src/phases/master.sh"

  # The watcher must check for BOTH spec.md AND spec.user_approved
  if grep -q 'spec.user_approved' "$plugin" 2>/dev/null; then
    # It must NOT have the old auto-approve pattern (spec.md only)
    if grep -Fq "auto-approved" "$plugin" 2>/dev/null; then
      printf 'FAIL %s: master.sh still has auto-approve logic\n' "$id" >&2
      FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    else
      flowai_test_pass "$id" "Spec approval requires user_approved marker (not auto)"
    fi
  else
    printf 'FAIL %s: master.sh does not reference spec.user_approved marker\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── SIG-009: tasks.sh emits tasks_produced and waits for master approval ────
# Tasks must NOT use flowai_phase_run_loop (which has a human gum gate).
# Instead it emits tasks_produced and waits for tasks.master_approved.
flowai_test_s_sig_009() {
  local id="SIG-009"
  local plugin="$FLOWAI_HOME/src/phases/tasks.sh"

  local has_event has_master_signal has_no_run_loop
  has_event=false
  has_master_signal=false
  has_no_run_loop=true

  grep -q 'tasks_produced' "$plugin" 2>/dev/null && has_event=true
  grep -q 'tasks.master_approved' "$plugin" 2>/dev/null && has_master_signal=true
  grep -q 'flowai_phase_run_loop' "$plugin" 2>/dev/null && has_no_run_loop=false

  if $has_event && $has_master_signal && $has_no_run_loop; then
    flowai_test_pass "$id" "Tasks uses Master approval (no human gum gate)"
  else
    printf 'FAIL %s: tasks.sh contract broken (event=%s master_signal=%s no_run_loop=%s)\n' \
      "$id" "$has_event" "$has_master_signal" "$has_no_run_loop" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# SIG-010 — Master DIRECTIVE includes MEMORY LEARNING PROTOCOL
# The Master Agent must have memory learning instructions in its DIRECTIVE
# and in the rejection-handling prompt, referencing the constitution file.
flowai_test_s_sig_010() {
  local id="SIG-010"
  local master="$FLOWAI_HOME/src/phases/master.sh"

  local has_protocol has_memory_file has_rejection_memory
  has_protocol=false
  has_memory_file=false
  has_rejection_memory=false

  grep -q 'MEMORY LEARNING PROTOCOL' "$master" 2>/dev/null && has_protocol=true
  grep -q 'MEMORY_FILE' "$master" 2>/dev/null && has_memory_file=true
  grep -q 'MEMORY LEARNING.*analyze.*user.*feedback' "$master" 2>/dev/null && has_rejection_memory=true

  if $has_protocol && $has_memory_file && $has_rejection_memory; then
    flowai_test_pass "$id" "Master includes adaptive memory learning protocol"
  else
    printf 'FAIL %s: master.sh memory protocol missing (protocol=%s memory_file=%s rejection=%s)\n' \
      "$id" "$has_protocol" "$has_memory_file" "$has_rejection_memory" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# SIG-011 — Tasks has retry loop for Master rejection
# tasks.sh must poll for tasks.rejection_context and re-run AI on rejection,
# preventing pipeline deadlock when Master AI rejects the task breakdown.
flowai_test_s_sig_011() {
  local id="SIG-011"
  local plugin="$FLOWAI_HOME/src/phases/tasks.sh"

  local has_rejection_poll has_retry_loop has_approved_poll
  has_rejection_poll=false
  has_retry_loop=false
  has_approved_poll=false

  grep -q 'tasks.rejection_context' "$plugin" 2>/dev/null && has_rejection_poll=true
  grep -q 'while true' "$plugin" 2>/dev/null && has_retry_loop=true
  grep -q 'tasks.master_approved.ready' "$plugin" 2>/dev/null && has_approved_poll=true

  if $has_rejection_poll && $has_retry_loop && $has_approved_poll; then
    flowai_test_pass "$id" "Tasks has retry loop for Master rejection"
  else
    printf 'FAIL %s: tasks.sh missing retry loop (rejection=%s loop=%s approved=%s)\n' \
      "$id" "$has_rejection_poll" "$has_retry_loop" "$has_approved_poll" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# SIG-012 — Master tasks review uses VERDICT format and fails closed
# master.sh must use machine-parsable VERDICT format and default to REJECTED on error.
flowai_test_s_sig_012() {
  local id="SIG-012"
  local master="$FLOWAI_HOME/src/phases/master.sh"

  local has_verdict_format has_fail_closed
  has_verdict_format=false
  has_fail_closed=false

  # Check that master uses verdict_line parsing (last line) with VERDICT: APPROVED
  grep -q 'verdict_line' "$master" 2>/dev/null \
    && grep -q 'VERDICT:.*APPROVED' "$master" 2>/dev/null \
    && has_verdict_format=true
  # Check fail-closed: AI error defaults to REJECTED
  grep -q 'REJECTED.*AI review failed' "$master" 2>/dev/null && has_fail_closed=true

  if $has_verdict_format && $has_fail_closed; then
    flowai_test_pass "$id" "Master tasks review uses VERDICT format and fails closed"
  else
    printf 'FAIL %s: master.sh review contract broken (verdict=%s fail_closed=%s)\n' \
      "$id" "$has_verdict_format" "$has_fail_closed" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# SIG-013 — Memory file resolves to constitution + constitution injected in prompts
# Docs §6: Master resolves MEMORY_FILE to .specify/memory/constitution.md
# Docs §5: skills.sh injects [PROJECT CONSTITUTION] block into every agent's prompt
flowai_test_s_sig_013() {
  local id="SIG-013"
  local master="$FLOWAI_HOME/src/phases/master.sh"
  local skills="$FLOWAI_HOME/src/core/skills.sh"

  local has_path_resolution has_fallback has_constitution_inject
  has_path_resolution=false
  has_fallback=false
  has_constitution_inject=false

  grep -q 'flowai_specify_constitution_path' "$master" 2>/dev/null && has_path_resolution=true
  grep -q '.specify/memory/constitution.md' "$master" 2>/dev/null && has_fallback=true
  grep -q 'PROJECT CONSTITUTION' "$skills" 2>/dev/null && has_constitution_inject=true

  if $has_path_resolution && $has_fallback && $has_constitution_inject; then
    flowai_test_pass "$id" "Memory file resolves to constitution + injected in prompts"
  else
    printf 'FAIL %s: memory path broken (resolve=%s fallback=%s inject=%s)\n' \
      "$id" "$has_path_resolution" "$has_fallback" "$has_constitution_inject" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# SIG-014 — Implement phase stays alive: touches impl.code_complete + polls impl.ready
# Docs §4: After impl_produced, Review unblocks; Impl polls for impl.ready (no flowai_phase_run_loop)
flowai_test_s_sig_014() {
  local id="SIG-014"
  local impl="$FLOWAI_HOME/src/phases/implement.sh"

  local has_stay_alive has_ready_poll has_rejection_poll has_no_run_loop has_impl_produced has_code_complete
  has_stay_alive=false
  has_ready_poll=false
  has_rejection_poll=false
  has_no_run_loop=true
  has_impl_produced=false
  has_code_complete=false

  grep -q 'while true' "$impl" 2>/dev/null && has_stay_alive=true
  grep -q 'impl.ready' "$impl" 2>/dev/null && has_ready_poll=true
  grep -q 'impl.rejection_context\|REJECTION_CONTEXT_FILE' "$impl" 2>/dev/null && has_rejection_poll=true
  grep -q 'flowai_phase_run_loop' "$impl" 2>/dev/null && has_no_run_loop=false
  grep -q 'impl_produced' "$impl" 2>/dev/null && has_impl_produced=true
  grep -q 'impl.code_complete.ready' "$impl" 2>/dev/null && has_code_complete=true
  local has_focus_review=false
  grep -q 'flowai_phase_focus "review"' "$impl" 2>/dev/null && has_focus_review=true

  if $has_stay_alive && $has_ready_poll && $has_rejection_poll && $has_no_run_loop && $has_impl_produced && $has_code_complete && $has_focus_review; then
    flowai_test_pass "$id" "Implement: impl.code_complete + focus Review + polls impl.ready"
  else
    printf 'FAIL %s: implement.sh contract broken (alive=%s ready=%s reject=%s no_loop=%s produced=%s code_complete=%s focus_review=%s)\n' \
      "$id" "$has_stay_alive" "$has_ready_poll" "$has_rejection_poll" "$has_no_run_loop" "$has_impl_produced" "$has_code_complete" "$has_focus_review" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# SIG-015 — Review phase uses gum gate + writes impl.rejection_context
# Docs §5: Review writes rejection context to impl.rejection_context for Impl re-runs
flowai_test_s_sig_015() {
  local id="SIG-015"
  local review="$FLOWAI_HOME/src/phases/review.sh"

  local has_run_loop has_rejection_path
  has_run_loop=false
  has_rejection_path=false

  grep -q 'flowai_phase_run_loop' "$review" 2>/dev/null && has_run_loop=true
  grep -q 'impl.rejection_context' "$review" 2>/dev/null && has_rejection_path=true
  grep -q 'impl.code_complete' "$review" 2>/dev/null && has_code_complete_wait=true || has_code_complete_wait=false

  if $has_run_loop && $has_rejection_path && $has_code_complete_wait; then
    flowai_test_pass "$id" "Review waits impl.code_complete + gum gate + impl.rejection_context"
  else
    printf 'FAIL %s: review.sh contract broken (run_loop=%s rejection=%s code_complete=%s)\n' \
      "$id" "$has_run_loop" "$has_rejection_path" "$has_code_complete_wait" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# SIG-016 — Start cleans ALL signal file types (not just .ready)
# Prevents stale rejection_context, reject, or user_approved from previous runs
flowai_test_s_sig_016() {
  local id="SIG-016"
  local start="$FLOWAI_HOME/src/commands/start.sh"

  local cleans_ready cleans_reject cleans_rejection_ctx cleans_user_approved
  cleans_ready=false
  cleans_reject=false
  cleans_rejection_ctx=false
  cleans_user_approved=false

  grep -q '\.ready' "$start" 2>/dev/null && grep -q 'rm -f.*signals.*\.ready' "$start" 2>/dev/null && cleans_ready=true
  grep -q 'rm -f.*signals.*\.reject' "$start" 2>/dev/null && cleans_reject=true
  grep -q 'rm -f.*signals.*\.rejection_context' "$start" 2>/dev/null && cleans_rejection_ctx=true
  grep -q 'rm -f.*signals.*\.user_approved' "$start" 2>/dev/null && cleans_user_approved=true

  if $cleans_ready && $cleans_reject && $cleans_rejection_ctx && $cleans_user_approved; then
    flowai_test_pass "$id" "Start cleans all signal types (ready, reject, rejection_context, user_approved)"
  else
    printf 'FAIL %s: start.sh missing signal cleanup (ready=%s reject=%s ctx=%s approved=%s)\n' \
      "$id" "$cleans_ready" "$cleans_reject" "$cleans_rejection_ctx" "$cleans_user_approved" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# SIG-017 — flowai_ai_run_oneshot exists in ai.sh and fails closed
# Docs: Master uses one-shot AI for tasks review — function must exist and fail closed
flowai_test_s_sig_017() {
  local id="SIG-017"
  local ai="$FLOWAI_HOME/src/core/ai.sh"

  local has_function has_fail_closed
  has_function=false
  has_fail_closed=false

  grep -q 'flowai_ai_run_oneshot()' "$ai" 2>/dev/null && has_function=true
  grep -q 'VERDICT: REJECTED' "$ai" 2>/dev/null && has_fail_closed=true

  if $has_function && $has_fail_closed; then
    flowai_test_pass "$id" "flowai_ai_run_oneshot exists in ai.sh and fails closed"
  else
    printf 'FAIL %s: ai.sh oneshot broken (function=%s fail_closed=%s)\n' \
      "$id" "$has_function" "$has_fail_closed" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# SIG-018 — Memory learning protocol covers approve AND reject paths
# Docs §6: Master must instruct AI to persist on approve AND skip on reject
flowai_test_s_sig_018() {
  local id="SIG-018"
  local master="$FLOWAI_HOME/src/phases/master.sh"

  local has_append_rule has_user_consent has_ephemeral has_memory_path
  has_append_rule=false
  has_user_consent=false
  has_ephemeral=false
  has_memory_path=false

  grep -q 'Append the rule' "$master" 2>/dev/null && has_append_rule=true
  grep -q 'user.*approv\|explicit.*approv\|permission' "$master" 2>/dev/null && has_user_consent=true
  grep -q 'ephemeral\|this task only\|temporary' "$master" 2>/dev/null && has_ephemeral=true
  grep -q 'MEMORY_FILE' "$master" 2>/dev/null && has_memory_path=true

  if $has_append_rule && $has_user_consent && $has_ephemeral && $has_memory_path; then
    flowai_test_pass "$id" "Memory protocol covers approve (persist) and reject (ephemeral) paths"
  else
    printf 'FAIL %s: memory protocol incomplete (append=%s consent=%s ephemeral=%s path=%s)\n' \
      "$id" "$has_append_rule" "$has_user_consent" "$has_ephemeral" "$has_memory_path" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# SIG-019 — flowai_phase_artifact_boundary function exists in phase.sh
# Framework-level guard: every phase prompt gets artifact ownership rules.
flowai_test_s_sig_019() {
  local id="SIG-019"
  local phase="$FLOWAI_HOME/src/core/phase.sh"

  local has_function has_ownership_map has_violation_warning
  has_function=false
  has_ownership_map=false
  has_violation_warning=false

  grep -q 'flowai_phase_artifact_boundary()' "$phase" 2>/dev/null && has_function=true
  grep -q 'spec/master.*spec.md' "$phase" 2>/dev/null && has_ownership_map=true
  grep -q 'Violating this rule\|pipeline violation' "$phase" 2>/dev/null && has_violation_warning=true

  if $has_function && $has_ownership_map && $has_violation_warning; then
    flowai_test_pass "$id" "flowai_phase_artifact_boundary exists with ownership map"
  else
    printf 'FAIL %s: artifact boundary broken (function=%s ownership=%s violation=%s)\n' \
      "$id" "$has_function" "$has_ownership_map" "$has_violation_warning" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# SIG-020 — flowai_phase_write_prompt injects artifact boundary for all phases
# Every phase prompt composed via flowai_phase_write_prompt must include the
# artifact boundary rule — this is the architectural invariant.
flowai_test_s_sig_020() {
  local id="SIG-020"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai/launch"
  printf '{"master":{"tool":"gemini","model":"gemini-2.5-pro"}}' > "$scratch/.flowai/config.json"
  local role_file="$FLOWAI_HOME/src/roles/backend-engineer.md"
  local prompt_file content
  prompt_file="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s <<EOF
# shellcheck source=../../src/core/phase.sh
source "\$FLOWAI_HOME/src/core/phase.sh"
flowai_phase_write_prompt "plan" "$role_file" "TEST DIRECTIVE"
EOF
)"
  local ok=true
  if [[ -f "$prompt_file" ]]; then
    content="$(cat "$prompt_file")"
    if [[ "$content" != *"ARTIFACT BOUNDARY"* ]]; then
      printf 'FAIL %s: prompt missing ARTIFACT BOUNDARY block\n' "$id" >&2
      ok=false
    fi
    if [[ "$content" != *"Violating this rule"* ]] && [[ "$content" != *"pipeline violation"* ]]; then
      printf 'FAIL %s: prompt missing pipeline violation warning\n' "$id" >&2
      ok=false
    fi
    if [[ "$content" != *"plan"* ]]; then
      printf 'FAIL %s: prompt does not contain phase name\n' "$id" >&2
      ok=false
    fi
  else
    printf 'FAIL %s: prompt file not created\n' "$id" >&2
    ok=false
  fi
  if $ok; then
    flowai_test_pass "$id" "flowai_phase_write_prompt injects artifact boundary"
  else
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# SIG-021 — Pipeline Coordination preamble includes artifact ownership rule
# The skills.sh preamble must enforce artifact ownership for ALL agents.
flowai_test_s_sig_021() {
  local id="SIG-021"
  local skills="$FLOWAI_HOME/src/core/skills.sh"

  local has_ownership has_only_create has_violation
  has_ownership=false
  has_only_create=false
  has_violation=false

  grep -q 'FILE CREATION\|Artifacts & Ownership' "$skills" 2>/dev/null && has_ownership=true
  grep -q 'ONLY write to the OUTPUT FILE\|ONLY create or modify' "$skills" 2>/dev/null && has_only_create=true
  grep -q 'PROHIBITED file patterns\|pipeline violation' "$skills" 2>/dev/null && has_violation=true

  if $has_ownership && $has_only_create && $has_violation; then
    flowai_test_pass "$id" "Pipeline Coordination includes artifact ownership enforcement"
  else
    printf 'FAIL %s: skills.sh artifact ownership missing (section=%s only_create=%s violation=%s)\n' \
      "$id" "$has_ownership" "$has_only_create" "$has_violation" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# SIG-022 — Master post-QA review prompt prohibits file creation
# Master's oneshot review must be verbal only — no artifact creation.
flowai_test_s_sig_022() {
  local id="SIG-022"
  local master="$FLOWAI_HOME/src/phases/master.sh"

  local has_verbal_only has_no_create_files has_boundary_call
  has_verbal_only=false
  has_no_create_files=false
  has_boundary_call=false

  grep -q 'VERBAL review' "$master" 2>/dev/null && has_verbal_only=true
  grep -q 'Do NOT create any files' "$master" 2>/dev/null && has_no_create_files=true
  grep -q 'flowai_phase_artifact_boundary.*master' "$master" 2>/dev/null && has_boundary_call=true

  if $has_verbal_only && $has_no_create_files && $has_boundary_call; then
    flowai_test_pass "$id" "Master post-QA review is verbal-only with artifact boundary"
  else
    printf 'FAIL %s: master.sh review file-creation guard missing (verbal=%s no_create=%s boundary=%s)\n' \
      "$id" "$has_verbal_only" "$has_no_create_files" "$has_boundary_call" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# SIG-023 — Pipeline Coordination preamble enforces Spec-Driven Development
# Spec.md must be declared the authoritative source of truth for all agents.
flowai_test_s_sig_023() {
  local id="SIG-023"
  local skills="$FLOWAI_HOME/src/core/skills.sh"

  local has_spec_authority has_source_of_truth has_acceptance_criteria has_spec_wins
  has_spec_authority=false
  has_source_of_truth=false
  has_acceptance_criteria=false
  has_spec_wins=false

  grep -q 'SPEC IS TRUTH\|Specification Authority' "$skills" 2>/dev/null && has_spec_authority=true
  grep -q 'single source of truth\|AUTHORITATIVE' "$skills" 2>/dev/null && has_source_of_truth=true
  grep -q 'acceptance criteria' "$skills" 2>/dev/null && has_acceptance_criteria=true
  grep -q 'spec wins' "$skills" 2>/dev/null && has_spec_wins=true

  if $has_spec_authority && $has_source_of_truth && $has_acceptance_criteria && $has_spec_wins; then
    flowai_test_pass "$id" "Pipeline Coordination enforces Spec-Driven Development"
  else
    printf 'FAIL %s: spec-driven enforcement missing (authority=%s truth=%s criteria=%s wins=%s)\n' \
      "$id" "$has_spec_authority" "$has_source_of_truth" "$has_acceptance_criteria" "$has_spec_wins" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# SIG-024 — flowai_ai_run_oneshot enriches prompts with knowledge graph context
# Oneshot calls must inject the graph block so review agents navigate efficiently.
flowai_test_s_sig_024() {
  local id="SIG-024"
  local ai="$FLOWAI_HOME/src/core/ai.sh"

  local has_graph_check has_enrichment has_cleanup
  has_graph_check=false
  has_enrichment=false
  has_cleanup=false

  grep -q 'flowai_graph_is_enabled' "$ai" 2>/dev/null && has_graph_check=true
  grep -q 'enriched_prompt' "$ai" 2>/dev/null && has_enrichment=true
  grep -q 'rm -f.*enriched_prompt' "$ai" 2>/dev/null && has_cleanup=true

  if $has_graph_check && $has_enrichment && $has_cleanup; then
    flowai_test_pass "$id" "flowai_ai_run_oneshot enriches with graph context"
  else
    printf 'FAIL %s: oneshot graph enrichment missing (graph_check=%s enrichment=%s cleanup=%s)\n' \
      "$id" "$has_graph_check" "$has_enrichment" "$has_cleanup" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# SIG-026 — Knowledge graph context block enforces graph-first navigation
flowai_test_s_sig_026() {
  local id="SIG-026"
  local graph="$FLOWAI_HOME/src/core/graph.sh"

  local has_navigate has_no_blind_search has_embedded
  has_navigate=false
  has_no_blind_search=false
  has_embedded=false

  grep -q 'USE THIS MAP to navigate' "$graph" 2>/dev/null && has_navigate=true
  grep -q 'Do NOT search files blindly' "$graph" 2>/dev/null && has_no_blind_search=true
  grep -q 'report_content' "$graph" 2>/dev/null && has_embedded=true

  if $has_navigate && $has_no_blind_search && $has_embedded; then
    flowai_test_pass "$id" "Graph context block enforces navigation with embedded report content"
  else
    printf 'FAIL %s: graph protocol not mandatory (navigate=%s no_blind=%s embedded=%s)\n' \
      "$id" "$has_navigate" "$has_no_blind_search" "$has_embedded" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# SIG-027 — Claude oneshot does NOT hardcode graph-only system prompt
# The oneshot function must use a generic system prompt, not "knowledge graph extraction engine"
flowai_test_s_sig_027() {
  local id="SIG-027"
  local claude="$FLOWAI_HOME/src/tools/claude.sh"

  local has_generic_prompt has_no_graph_hardcode
  has_generic_prompt=false
  has_no_graph_hardcode=true

  grep -q 'Follow the directive' "$claude" 2>/dev/null && has_generic_prompt=true
  grep -q 'knowledge graph extraction engine' "$claude" 2>/dev/null && has_no_graph_hardcode=false

  if $has_generic_prompt && $has_no_graph_hardcode; then
    flowai_test_pass "$id" "Claude oneshot uses generic system prompt (not graph-only)"
  else
    printf 'FAIL %s: claude.sh oneshot broken (generic=%s no_hardcode=%s)\n' \
      "$id" "$has_generic_prompt" "$has_no_graph_hardcode" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# SIG-028 — Pipeline Coordination HARD CONSTRAINTS are at the top of preamble
# The most critical rules (file creation, graph first, spec is truth) must be
# the FIRST section agents see, not buried after softer orchestration rules.
flowai_test_s_sig_028() {
  local id="SIG-028"
  local skills="$FLOWAI_HOME/src/core/skills.sh"

  local has_hard_constraints has_graph_first has_file_creation
  has_hard_constraints=false
  has_graph_first=false
  has_file_creation=false

  grep -q 'HARD CONSTRAINTS' "$skills" 2>/dev/null && has_hard_constraints=true
  grep -q 'GRAPH FIRST' "$skills" 2>/dev/null && has_graph_first=true
  grep -q 'FILE CREATION' "$skills" 2>/dev/null && has_file_creation=true

  if $has_hard_constraints && $has_graph_first && $has_file_creation; then
    flowai_test_pass "$id" "HARD CONSTRAINTS section at top of Pipeline Coordination"
  else
    printf 'FAIL %s: hard constraints missing (section=%s graph=%s file=%s)\n' \
      "$id" "$has_hard_constraints" "$has_graph_first" "$has_file_creation" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# SIG-029 — HARD CONSTRAINTS appear BEFORE role content in composed prompt
# The prompt builder must inject PIPELINE COORDINATION (with HARD CONSTRAINTS)
# at the TOP of the system prompt, before the role file content. LLMs weight
# instructions near the beginning of the context window more heavily.
flowai_test_s_sig_029() {
  local id="SIG-029"
  local skills="$FLOWAI_HOME/src/core/skills.sh"

  # Check that the Pipeline Coordination block is prepended (before the prompt_file content),
  # not appended after it. The code must set prompt= with the preamble FIRST, then cat prompt_file.
  local preamble_first=false
  # The preamble is assigned to prompt= before the prompt_file is appended.
  # Look for: prompt starts with the coordination block, then prompt_file is added later.
  if grep -q 'local prompt="---.*PIPELINE COORDINATION' "$skills" 2>/dev/null; then
    preamble_first=true
  fi

  if $preamble_first; then
    flowai_test_pass "$id" "HARD CONSTRAINTS are FIRST in composed prompt (before role content)"
  else
    printf 'FAIL %s: HARD CONSTRAINTS must be at START of prompt (before role file)\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# SIG-030 — Claude tool uses --append-system-prompt for constraint reinforcement
# The "sandwich" technique: constraints at the top of system prompt AND appended
# at the end ensures LLMs see mandatory rules at both edges of the context window.
flowai_test_s_sig_030() {
  local id="SIG-030"
  local claude_sh="$FLOWAI_HOME/src/tools/claude.sh"

  local has_append has_reminder
  has_append=false
  has_reminder=false

  grep -q '\-\-append-system-prompt' "$claude_sh" 2>/dev/null && has_append=true
  grep -q 'CONSTRAINT_REMINDER\|MANDATORY RULES' "$claude_sh" 2>/dev/null && has_reminder=true

  if $has_append && $has_reminder; then
    flowai_test_pass "$id" "Claude tool appends constraint reminder (sandwich reinforcement)"
  else
    printf 'FAIL %s: Missing --append-system-prompt reinforcement (append=%s reminder=%s)\n' \
      "$id" "$has_append" "$has_reminder" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# SIG-031 — Non-interactive -p message reinforces constraints (not generic)
# The user message sent via -p must reference HARD CONSTRAINTS and OUTPUT FILE
# restrictions — a vague "begin immediately" lets Claude default to its own behaviors.
flowai_test_s_sig_031() {
  local id="SIG-031"
  local claude_sh="$FLOWAI_HOME/src/tools/claude.sh"
  local gemini_sh="$FLOWAI_HOME/src/tools/gemini.sh"

  local claude_ok=false gemini_ok=false

  if grep -q 'HARD CONSTRAINTS.*MANDATORY\|ONLY write to the OUTPUT FILE' "$claude_sh" 2>/dev/null; then
    claude_ok=true
  fi
  if grep -q 'HARD CONSTRAINTS.*MANDATORY\|ONLY write to the OUTPUT FILE' "$gemini_sh" 2>/dev/null; then
    gemini_ok=true
  fi

  if $claude_ok && $gemini_ok; then
    flowai_test_pass "$id" "Non-interactive -p message reinforces constraints in Claude and Gemini"
  else
    printf 'FAIL %s: -p message must reinforce constraints (claude=%s gemini=%s)\n' \
      "$id" "$claude_ok" "$gemini_ok" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# SIG-032 — Claude tool applies phase-aware tool restrictions
# The review phase must disallow Write to prevent Claude from creating files.
# Other phases rely on prompt enforcement since Claude Code --disallowed-tools
# doesn't support path-based patterns.
flowai_test_s_sig_032() {
  local id="SIG-032"
  local claude_sh="$FLOWAI_HOME/src/tools/claude.sh"

  local has_phase_check has_review_disallow has_env_var
  has_phase_check=false
  has_review_disallow=false
  has_env_var=false

  grep -q 'FLOWAI_CURRENT_PHASE' "$claude_sh" 2>/dev/null && has_phase_check=true
  # review case + disallowed-tools Write can be on separate lines in the case block
  if grep -q 'review)' "$claude_sh" 2>/dev/null && grep -q 'disallowed-tools.*Write\|disallowed.*Write' "$claude_sh" 2>/dev/null; then
    has_review_disallow=true
  fi
  grep -q 'FLOWAI_CURRENT_PHASE' "$FLOWAI_HOME/src/core/ai.sh" 2>/dev/null && has_env_var=true

  if $has_phase_check && $has_review_disallow && $has_env_var; then
    flowai_test_pass "$id" "Claude tool applies phase-aware tool restrictions (review disallows Write)"
  else
    printf 'FAIL %s: Missing phase restrictions (check=%s review=%s env=%s)\n' \
      "$id" "$has_phase_check" "$has_review_disallow" "$has_env_var" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# SIG-033 — Tool-agnostic project config injection in start.sh
# start.sh must call the tool-agnostic dispatcher (flowai_ai_inject_all_tool_configs)
# instead of hardcoding injection for a specific tool.
flowai_test_s_sig_033() {
  local id="SIG-033"
  local start_sh="$FLOWAI_HOME/src/commands/start.sh"
  local ai_sh="$FLOWAI_HOME/src/core/ai.sh"

  local has_dispatcher has_graph_check has_content_fn
  has_dispatcher=false
  has_graph_check=false
  has_content_fn=false

  grep -q 'flowai_ai_inject_all_tool_configs' "$start_sh" 2>/dev/null && has_dispatcher=true
  grep -q 'flowai_graph_exists\|graph_exists' "$start_sh" 2>/dev/null && has_graph_check=true
  grep -q 'flowai_ai_project_config_content' "$ai_sh" 2>/dev/null && has_content_fn=true

  if $has_dispatcher && $has_graph_check && $has_content_fn; then
    flowai_test_pass "$id" "start.sh uses tool-agnostic dispatcher for project config injection"
  else
    printf 'FAIL %s: Missing tool-agnostic injection (dispatcher=%s graph=%s content=%s)\n' \
      "$id" "$has_dispatcher" "$has_graph_check" "$has_content_fn" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# SIG-034 — All tool plugins implement _inject_project_config with markers
# Each tool must handle its own file format/location but use the shared
# FLOWAI:START/END markers to preserve user content.
flowai_test_s_sig_034() {
  local id="SIG-034"
  local ok=true

  for tool in claude gemini cursor copilot; do
    local tool_sh="$FLOWAI_HOME/src/tools/${tool}.sh"
    if ! grep -q "flowai_tool_${tool}_inject_project_config" "$tool_sh" 2>/dev/null; then
      printf 'FAIL %s: %s.sh missing _inject_project_config()\n' "$id" "$tool" >&2
      ok=false
    fi
    if ! grep -q 'FLOWAI:START' "$tool_sh" 2>/dev/null; then
      printf 'FAIL %s: %s.sh missing FLOWAI:START marker\n' "$id" "$tool" >&2
      ok=false
    fi
  done

  if $ok; then
    flowai_test_pass "$id" "All tool plugins implement _inject_project_config with markers"
  else
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# SIG-035 — Interactive mode sends initial prompt to anchor agent behavior
# Without an initial user message, Claude/Gemini open a blank session and
# respond to whatever the user types — ignoring the pipeline directive.
flowai_test_s_sig_035() {
  local id="SIG-035"

  local claude_ok=false gemini_ok=false
  # Claude: check for initial prompt in interactive path (not -p)
  if grep -q 'STAGED WORKFLOW.*step 1\|PIPELINE DIRECTIVE.*HARD CONSTRAINTS' \
    "$FLOWAI_HOME/src/tools/claude.sh" 2>/dev/null; then
    claude_ok=true
  fi
  # Gemini: check for initial prompt in interactive path
  if grep -q 'STAGED WORKFLOW.*step 1\|PIPELINE DIRECTIVE.*HARD CONSTRAINTS' \
    "$FLOWAI_HOME/src/tools/gemini.sh" 2>/dev/null; then
    gemini_ok=true
  fi

  if $claude_ok && $gemini_ok; then
    flowai_test_pass "$id" "Interactive mode sends initial prompt to anchor agent behavior"
  else
    printf 'FAIL %s: Missing initial prompt (claude=%s gemini=%s)\n' \
      "$id" "$claude_ok" "$gemini_ok" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# SIG-025 — All phase directives reference spec.md in CONTEXT
# Every downstream phase must read spec.md as an upstream artifact.
flowai_test_s_sig_025() {
  local id="SIG-025"
  local ok=true

  for phase_file in plan.sh tasks.sh implement.sh review.sh; do
    local f="$FLOWAI_HOME/src/phases/$phase_file"
    if [[ ! -f "$f" ]]; then
      printf 'FAIL %s: %s not found\n' "$id" "$phase_file" >&2
      ok=false
      continue
    fi
    if ! grep -q 'spec.md' "$f" 2>/dev/null; then
      printf 'FAIL %s: %s does not reference spec.md\n' "$id" "$phase_file" >&2
      ok=false
    fi
  done

  if $ok; then
    flowai_test_pass "$id" "All downstream phases reference spec.md in CONTEXT"
  else
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}
