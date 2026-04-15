#!/usr/bin/env bash
# Extended orchestration & signal protocol tests — verdict regex edge cases,
# phase timeout / pre-signal fast path, feature directory resolution,
# constraint reminder constant, and tool plugin API completeness.
# shellcheck shell=bash
# shellcheck disable=SC2016  # bash -c strings use $ vars for inner shell, not outer

# shellcheck source=../../src/core/log.sh
source "$FLOWAI_HOME/src/core/log.sh"

# ─── ORCHE-001: Verdict regex rejects "VERDICT: CONDITIONALLY APPROVED" ─────
# Prevents: false positive when AI hedges with "CONDITIONALLY APPROVED".
flowai_test_s_orche_001() {
  local id="ORCHE-001"
  local verdict_line='VERDICT: CONDITIONALLY APPROVED'
  local is_approved=false
  if [[ "$verdict_line" =~ ^[[:space:]]*VERDICT:[[:space:]]*APPROVED[[:space:]]*$ ]]; then
    is_approved=true
  fi
  if ! $is_approved; then
    flowai_test_pass "$id" "verdict CONDITIONALLY APPROVED does not match strict APPROVED regex"
  else
    printf 'FAIL %s: CONDITIONALLY APPROVED must not match\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── ORCHE-002: Verdict regex rejects "VERDICT: APPROVED BUT..." ────────────
# Prevents: false positive when AI adds trailing qualification.
flowai_test_s_orche_002() {
  local id="ORCHE-002"
  local verdict_line='VERDICT: APPROVED BUT needs cleanup'
  local is_approved=false
  if [[ "$verdict_line" =~ ^[[:space:]]*VERDICT:[[:space:]]*APPROVED[[:space:]]*$ ]]; then
    is_approved=true
  fi
  if ! $is_approved; then
    flowai_test_pass "$id" "verdict APPROVED BUT... does not match strict APPROVED regex"
  else
    printf 'FAIL %s: APPROVED BUT must not match\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── ORCHE-003: Verdict regex accepts whitespace-padded APPROVED ─────────────
# Ensures: leading/trailing whitespace is tolerated by the regex.
flowai_test_s_orche_003() {
  local id="ORCHE-003"
  local verdict_line='  VERDICT:  APPROVED  '
  local is_approved=false
  if [[ "$verdict_line" =~ ^[[:space:]]*VERDICT:[[:space:]]*APPROVED[[:space:]]*$ ]]; then
    is_approved=true
  fi
  if $is_approved; then
    flowai_test_pass "$id" "verdict with leading/trailing whitespace matches strict regex"
  else
    printf 'FAIL %s: whitespace-padded APPROVED should match\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# ─── ORCHE-004: Phase wait_for returns non-zero on timeout ──────────────────
# Prevents: pipeline hangs when a signal never arrives.
flowai_test_s_orche_004() {
  local id="ORCHE-004"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai/signals"
  printf '{}' > "$scratch/.flowai/config.json"
  local rc=0
  local _fh="$FLOWAI_HOME"
  # Use subshell with internal alarm for macOS compatibility (no GNU timeout).
  # FLOWAI_PHASE_TIMEOUT_SEC=1 makes wait_for self-terminate after 1s, but the
  # sleep in wait_for is 2s per loop, so add a 5s kill guard.
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$_fh" FLOWAI_PHASE_TIMEOUT_SEC=1 \
    bash -c '
      ( sleep 5; kill $$ 2>/dev/null ) &
      source "$FLOWAI_HOME/src/core/phase.sh"
      flowai_phase_wait_for "never_arrives" "orche-timeout-test"
    ' 2>/dev/null || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    flowai_test_pass "$id" "wait_for exits non-zero when signal times out"
  else
    printf 'FAIL %s: expected non-zero rc on timeout, got %s\n' "$id" "$rc" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── ORCHE-005: Phase wait_for returns immediately when signal pre-exists ───
# Prevents: unnecessary polling when signal file already on disk.
flowai_test_s_orche_005() {
  local id="ORCHE-005"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai/signals"
  printf '{}' > "$scratch/.flowai/config.json"
  touch "$scratch/.flowai/signals/preexist.ready"
  local rc=0
  local _fh="$FLOWAI_HOME"
  env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$_fh" bash -s <<'EOS' || rc=$?
source "$FLOWAI_HOME/src/core/phase.sh"
flowai_phase_wait_for "preexist" "orche-preexist-test"
EOS
  if [[ "$rc" -eq 0 ]]; then
    flowai_test_pass "$id" "wait_for returns 0 immediately when signal pre-exists"
  else
    printf 'FAIL %s: expected rc=0 for pre-existing signal, got %s\n' "$id" "$rc" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── ORCHE-006: Feature directory resolution prefers git branch name ────────
# Prevents: gum chooser ambiguity when specs/<branch>/ matches current branch.
flowai_test_s_orche_006() {
  local id="ORCHE-006"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  mkdir -p "$scratch/specs/feat-test-branch"
  printf '# test spec\n' > "$scratch/specs/feat-test-branch/spec.md"
  printf '{}' > "$scratch/.flowai/config.json"

  # Init a git repo and create a branch named feat-test-branch
  git -C "$scratch" init -q 2>/dev/null
  git -C "$scratch" checkout -b feat-test-branch -q 2>/dev/null
  # Need at least one commit for rev-parse to work
  git -C "$scratch" -c user.name="test" -c user.email="test@test" commit --allow-empty -m "init" -q 2>/dev/null

  local result
  result="$(cd "$scratch" && env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$FLOWAI_HOME" FLOWAI_TESTING=1 bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/phase.sh"
flowai_phase_resolve_feature_dir
EOS
)"
  if [[ "$result" == *"specs/feat-test-branch"* ]]; then
    flowai_test_pass "$id" "feature dir resolution prefers git branch name"
  else
    printf 'FAIL %s: expected specs/feat-test-branch, got %s\n' "$id" "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── ORCHE-007: FLOWAI_CONSTRAINT_REMINDER constant is defined in ai.sh ─────
# Prevents: sandwich reinforcement silently dropping when constant is missing.
flowai_test_s_orche_007() {
  local id="ORCHE-007"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  printf '{}' > "$scratch/.flowai/config.json"
  local _fh="$FLOWAI_HOME"
  local reminder
  reminder="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$_fh" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/ai.sh"
printf '%s' "$FLOWAI_CONSTRAINT_REMINDER"
EOS
)"
  if [[ -n "$reminder" ]] && [[ "$reminder" == *"ONLY write to the OUTPUT FILE"* ]]; then
    flowai_test_pass "$id" "FLOWAI_CONSTRAINT_REMINDER is defined and contains output-file rule"
  else
    printf 'FAIL %s: FLOWAI_CONSTRAINT_REMINDER missing or wrong content\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}

# ─── ORCHE-008: Tool plugin API — all tools define required functions ────────
# Prevents: new tool plugin missing one of the three mandatory functions.
flowai_test_s_orche_008() {
  local id="ORCHE-008"
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  printf '{}' > "$scratch/.flowai/config.json"
  local _fh="$FLOWAI_HOME"
  local missing
  missing="$(env FLOWAI_DIR="$scratch/.flowai" FLOWAI_HOME="$_fh" bash -s <<'EOS'
source "$FLOWAI_HOME/src/core/ai.sh"
missing=""
for tool in claude gemini cursor copilot; do
  for fn in "flowai_tool_${tool}_run" "flowai_tool_${tool}_print_models" "flowai_tool_${tool}_run_oneshot"; do
    if ! declare -F "$fn" >/dev/null 2>&1; then
      missing="${missing}${fn} "
    fi
  done
done
printf '%s' "$missing"
EOS
)"
  if [[ -z "$missing" ]]; then
    flowai_test_pass "$id" "all tool plugins define _run, _print_models, _run_oneshot"
  else
    printf 'FAIL %s: missing functions: %s\n' "$id" "$missing" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
  rm -rf "$scratch"
}
