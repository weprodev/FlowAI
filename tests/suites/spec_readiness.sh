#!/usr/bin/env bash
# Spec readiness: trunk branches + specs/<branch>/spec.md
# shellcheck shell=bash

# shellcheck source=tests/lib/harness.sh
source "$FLOWAI_HOME/tests/lib/harness.sh"

: "${FLOWAI_HOME:?FLOWAI_HOME must point to the FlowAI installation root}"
# shellcheck source=src/core/spec-readiness.sh
source "$FLOWAI_HOME/src/core/spec-readiness.sh"

# SR-001 — no git repo: snapshot allows start (harness / non-git projects)
flowai_test_s_sr_001() {
  local id="SR-001"
  local tmp rc
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  set +e
  flowai_spec_snapshot_ready "$tmp"
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    flowai_test_pass "$id" "spec snapshot ready without git (non-blocking)"
  else
    printf 'FAIL %s: expected 0 without git, got %s\n' "$id" "$rc" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# SR-002 — develop (trunk) is not ready
flowai_test_s_sr_002() {
  local id="SR-002"
  local tmp rc
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  git -C "$tmp" init >/dev/null 2>&1
  git -C "$tmp" config user.email "t@test" && git -C "$tmp" config user.name "t"
  git -C "$tmp" commit --allow-empty -m init >/dev/null 2>&1
  git -C "$tmp" branch -M develop >/dev/null 2>&1
  set +e
  flowai_spec_snapshot_ready "$tmp"
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    flowai_test_pass "$id" "trunk branch develop is not spec-ready"
  else
    printf 'FAIL %s: expected non-zero on develop\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# SR-003 — feature branch without spec.md is not ready
flowai_test_s_sr_003() {
  local id="SR-003"
  local tmp rc
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  git -C "$tmp" init >/dev/null 2>&1
  git -C "$tmp" config user.email "t@test" && git -C "$tmp" config user.name "t"
  git -C "$tmp" commit --allow-empty -m init >/dev/null 2>&1
  git -C "$tmp" branch -M main >/dev/null 2>&1
  git -C "$tmp" checkout -b feat-no-spec >/dev/null 2>&1
  set +e
  flowai_spec_snapshot_ready "$tmp"
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    flowai_test_pass "$id" "feature branch without specs/<branch>/spec.md is not ready"
  else
    printf 'FAIL %s: expected non-zero without spec.md\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# SR-004 — feature branch with non-empty spec.md is ready
flowai_test_s_sr_004() {
  local id="SR-004"
  local tmp rc
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  git -C "$tmp" init >/dev/null 2>&1
  git -C "$tmp" config user.email "t@test" && git -C "$tmp" config user.name "t"
  git -C "$tmp" commit --allow-empty -m init >/dev/null 2>&1
  git -C "$tmp" branch -M main >/dev/null 2>&1
  git -C "$tmp" checkout -b feat-with-spec >/dev/null 2>&1
  mkdir -p "$tmp/specs/feat-with-spec"
  printf '# Hello\n\nBody.\n' >"$tmp/specs/feat-with-spec/spec.md"
  set +e
  flowai_spec_snapshot_ready "$tmp"
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    flowai_test_pass "$id" "feature branch with non-empty spec.md is ready"
  else
    printf 'FAIL %s: expected 0 with valid spec.md\n' "$id" "$rc" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# SR-005 — empty spec.md (whitespace only) is not ready
flowai_test_s_sr_005() {
  local id="SR-005"
  local tmp rc
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  git -C "$tmp" init >/dev/null 2>&1
  git -C "$tmp" config user.email "t@test" && git -C "$tmp" config user.name "t"
  git -C "$tmp" commit --allow-empty -m init >/dev/null 2>&1
  git -C "$tmp" branch -M main >/dev/null 2>&1
  git -C "$tmp" checkout -b feat-empty-spec >/dev/null 2>&1
  mkdir -p "$tmp/specs/feat-empty-spec"
  printf '   \n\t\n' >"$tmp/specs/feat-empty-spec/spec.md"
  set +e
  flowai_spec_snapshot_ready "$tmp"
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    flowai_test_pass "$id" "whitespace-only spec.md is not ready"
  else
    printf 'FAIL %s: expected non-zero for whitespace-only spec\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# SR-006 — start.sh wires spec readiness before tmux
flowai_test_s_sr_006() {
  local id="SR-006"
  local start="$FLOWAI_HOME/src/commands/start.sh"
  if grep -q 'spec-readiness.sh' "$start" 2>/dev/null \
    && grep -q 'flowai_spec_snapshot_ready' "$start" 2>/dev/null \
    && grep -q 'flowai_spec_ensure_before_session' "$start" 2>/dev/null; then
    flowai_test_pass "$id" "start.sh imports spec-readiness and enforces snapshot"
  else
    printf 'FAIL %s: start.sh must source spec-readiness and call ensure/snapshot\n' "$id" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# SR-007 — feature dir resolves to specs/<current-branch> when present (no spurious gum menu)
flowai_test_s_sr_007() {
  local id="SR-007"
  local tmp out
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/.flowai/signals"
  printf '{"master":{"tool":"gemini","model":"gemini-2.5-pro"},"pipeline":{"plan":"team-lead"}}' >"$tmp/.flowai/config.json"
  mkdir -p "$tmp/specs/develop" "$tmp/specs/my-feat"
  git -C "$tmp" init >/dev/null 2>&1
  git -C "$tmp" config user.email "t@test" && git -C "$tmp" config user.name "t"
  git -C "$tmp" commit --allow-empty -m init >/dev/null 2>&1
  git -C "$tmp" branch -M main >/dev/null 2>&1
  git -C "$tmp" checkout -b my-feat >/dev/null 2>&1

  out="$(cd "$tmp" && env FLOWAI_DIR="$tmp/.flowai" FLOWAI_HOME="$FLOWAI_HOME" bash -s 2>/dev/null <<'EOS'
source "$FLOWAI_HOME/src/core/phase.sh"
flowai_phase_resolve_feature_dir
EOS
)"
  if [[ "$out" == "$tmp/specs/my-feat" ]]; then
    flowai_test_pass "$id" "resolve_feature_dir prefers specs/<git-branch> when directory exists"
  else
    printf 'FAIL %s: expected specs dir my-feat, got %q\n' "$id" "$out" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}
