#!/usr/bin/env bash
# FlowAI test suite — phase signal coordination
# Tests the signal protocol, role resolution, and prompt composition.
# shellcheck shell=bash
#
# Temp projects: env FLOWAI_DIR=… bash -s <<'EOS' … EOS (avoids SC2030/SC2031 on export-in-subshell).

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
source "$FLOWAI_HOME/src/core/config.sh"
source "$FLOWAI_HOME/src/core/skills.sh"
source "$FLOWAI_HOME/src/core/eventlog.sh"
source "$FLOWAI_HOME/src/core/graph.sh" 2>/dev/null || true
flowai_skills_build_prompt "plan" "$FLOWAI_DIR/launch/test_prompt.md"
EOS
)"

  if [[ "$composed" == *"[PIPELINE COORDINATION]"* ]]; then
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

# SIG-014 — Implement phase stays alive: polls impl.ready + rejection_context
# Docs §4: After impl_produced, Impl polls for Master signals (no flowai_phase_run_loop)
flowai_test_s_sig_014() {
  local id="SIG-014"
  local impl="$FLOWAI_HOME/src/phases/implement.sh"

  local has_stay_alive has_ready_poll has_rejection_poll has_no_run_loop has_impl_produced
  has_stay_alive=false
  has_ready_poll=false
  has_rejection_poll=false
  has_no_run_loop=true
  has_impl_produced=false

  grep -q 'while true' "$impl" 2>/dev/null && has_stay_alive=true
  grep -q 'impl.ready' "$impl" 2>/dev/null && has_ready_poll=true
  grep -q 'impl.rejection_context\|REJECTION_CONTEXT_FILE' "$impl" 2>/dev/null && has_rejection_poll=true
  grep -q 'flowai_phase_run_loop' "$impl" 2>/dev/null && has_no_run_loop=false
  grep -q 'impl_produced' "$impl" 2>/dev/null && has_impl_produced=true

  if $has_stay_alive && $has_ready_poll && $has_rejection_poll && $has_no_run_loop && $has_impl_produced; then
    flowai_test_pass "$id" "Implement stays alive: polls impl.ready + rejection_context"
  else
    printf 'FAIL %s: implement.sh contract broken (alive=%s ready=%s reject=%s no_loop=%s produced=%s)\n' \
      "$id" "$has_stay_alive" "$has_ready_poll" "$has_rejection_poll" "$has_no_run_loop" "$has_impl_produced" >&2
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

  if $has_run_loop && $has_rejection_path; then
    flowai_test_pass "$id" "Review uses gum gate + writes impl.rejection_context"
  else
    printf 'FAIL %s: review.sh contract broken (run_loop=%s rejection=%s)\n' \
      "$id" "$has_run_loop" "$has_rejection_path" >&2
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
