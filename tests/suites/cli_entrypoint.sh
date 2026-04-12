#!/usr/bin/env bash
# CLI entrypoint & help — executable tests for application use cases in tests/usecases/0*-*.md
# Expects tests/lib/harness.sh sourced first (see tests/run.sh).
# shellcheck shell=bash

# UC-CLI-001 / tests/usecases/001-cli-no-subcommand.md
flowai_test_s_cli_001() {
  flowai_test_invoke
  flowai_test_assert_rc 1 "UC-CLI-001" || return
  flowai_test_assert_combined_contains "Usage" "UC-CLI-001" || return
  flowai_test_assert_combined_contains "FlowAI" "UC-CLI-001" || return
  flowai_test_assert_combined_contains "tip: run as fai" "UC-CLI-001" || return
  flowai_test_pass "UC-CLI-001" "flowai with no args prints usage and exits 1"
}

# UC-CLI-002 / tests/usecases/002-cli-help-command.md
flowai_test_s_cli_002() {
  flowai_test_invoke help
  flowai_test_assert_rc 0 "UC-CLI-002" || return
  flowai_test_assert_combined_contains "Usage" "UC-CLI-002" || return
  flowai_test_assert_combined_contains "tip: run as fai" "UC-CLI-002" || return
  flowai_test_pass "UC-CLI-002" "flowai help exits 0 and shows usage"
}

# UC-CLI-003 / tests/usecases/003-cli-help-short-flag.md
flowai_test_s_cli_003() {
  flowai_test_invoke -h
  flowai_test_assert_rc 0 "UC-CLI-003" || return
  flowai_test_assert_combined_contains "FlowAI" "UC-CLI-003" || return
  flowai_test_assert_combined_contains "tip: run as fai" "UC-CLI-003" || return
  flowai_test_pass "UC-CLI-003" "flowai -h exits 0 and shows usage"
}

# UC-CLI-007 / tests/usecases/007-cli-help-long-flag.md
flowai_test_s_cli_007() {
  flowai_test_invoke --help
  flowai_test_assert_rc 0 "UC-CLI-007" || return
  flowai_test_assert_combined_contains "FlowAI" "UC-CLI-007" || return
  flowai_test_assert_combined_contains "tip: run as fai" "UC-CLI-007" || return
  flowai_test_pass "UC-CLI-007" "flowai --help exits 0 and shows usage"
}

# UC-CLI-008 / tests/usecases/008-cli-version.md
flowai_test_s_cli_008() {
  local ver
  ver="$(head -n1 "$FLOWAI_HOME/VERSION" 2>/dev/null | tr -d '\r' || true)"
  flowai_test_invoke version
  flowai_test_assert_rc 0 "UC-CLI-008" || return
  flowai_test_assert_combined_contains "FlowAI" "UC-CLI-008" || return
  flowai_test_assert_combined_contains "$ver" "UC-CLI-008" || return

  flowai_test_invoke --version
  flowai_test_assert_rc 0 "UC-CLI-008" || return
  flowai_test_assert_combined_contains "$ver" "UC-CLI-008" || return

  flowai_test_pass "UC-CLI-008" "flowai version and --version print FlowAI and VERSION"
}

# UC-CLI-009 / tests/usecases/009-cli-run-contextual-help.md
flowai_test_s_cli_009() {
  flowai_test_invoke run --help
  flowai_test_assert_rc 0 "UC-CLI-009" || return
  flowai_test_assert_combined_contains "run" "UC-CLI-009" || return
  flowai_test_assert_combined_contains "phase" "UC-CLI-009" || return
  flowai_test_assert_combined_contains "master" "UC-CLI-009" || return
  flowai_test_pass "UC-CLI-009" "flowai run --help exits 0 and lists phases"
}

# UC-CLI-004 / tests/usecases/004-cli-unknown-subcommand.md
flowai_test_s_cli_004() {
  flowai_test_invoke not-a-real-command
  flowai_test_assert_rc 1 "UC-CLI-004" || return
  flowai_test_assert_combined_contains "Unknown command" "UC-CLI-004" || return
  flowai_test_pass "UC-CLI-004" "unknown subcommand exits 1 with error"
}

# UC-CLI-005 / tests/usecases/005-cli-run-missing-phase.md
flowai_test_s_cli_005() {
  flowai_test_invoke run
  flowai_test_assert_rc 1 "UC-CLI-005" || return
  flowai_test_assert_combined_contains "Usage: flowai run" "UC-CLI-005" || return
  flowai_test_pass "UC-CLI-005" "flowai run without phase exits 1"
}

# UC-CLI-006 / tests/usecases/006-cli-run-unknown-phase.md
flowai_test_s_cli_006() {
  flowai_test_invoke run definitely-not-a-phase-xyz
  flowai_test_assert_rc 1 "UC-CLI-006" || return
  flowai_test_assert_combined_contains "Unknown phase" "UC-CLI-006" || return
  flowai_test_pass "UC-CLI-006" "flowai run <unknown> exits 1"
}

# UC-CLI-027 / tests/usecases/027-cli-config-validate-ok.md
flowai_test_s_cli_027() {
  if flowai_test_skip_if_missing_jq "UC-CLI-027" "flowai validate happy path"; then return 0; fi
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  flowai_test_invoke_in_dir "$tmp" init
  flowai_test_assert_rc 0 "UC-CLI-027" || return

  flowai_test_invoke_in_dir "$tmp" validate
  flowai_test_assert_rc 0 "UC-CLI-027" || return
  flowai_test_assert_combined_contains "matches models-catalog" "UC-CLI-027" || return

  flowai_test_pass "UC-CLI-027" "flowai validate exits 0 on fresh init config"
}

# UC-CLI-025 / tests/usecases/025-cli-models-list.md
flowai_test_s_cli_025() {
  flowai_test_invoke models list
  flowai_test_assert_rc 0 "UC-CLI-025" || return
  flowai_test_assert_combined_contains "Valid models: gemini" "UC-CLI-025" || return
  flowai_test_assert_combined_contains "gemini-2.5-pro" "UC-CLI-025" || return
  flowai_test_assert_combined_contains "Valid models: claude" "UC-CLI-025" || return
  flowai_test_assert_combined_contains "sonnet" "UC-CLI-025" || return
  flowai_test_pass "UC-CLI-025" "flowai models list prints catalog for gemini and claude"
}

# UC-CLI-030 / tests/usecases/030-cli-fai-short-alias.md
flowai_test_s_cli_030() {
  flowai_test_assert_path_exists "$FLOWAI_HOME/bin/fai" "UC-CLI-030" || return
  local ver out err
  ver="$(head -n1 "$FLOWAI_HOME/VERSION" 2>/dev/null | tr -d '\r' || true)"
  out="$(mktemp)"
  err="$(mktemp)"
  set +e
  (cd "$FLOWAI_HOME" && FLOWAI_TESTING=1 ./bin/fai version) >"$out" 2>"$err"
  local rc=$?
  set -e
  export FLOWAI_TEST_RC=$rc
  FLOWAI_TEST_STDOUT="$(cat "$out")"
  export FLOWAI_TEST_STDOUT
  FLOWAI_TEST_STDERR="$(cat "$err")"
  export FLOWAI_TEST_STDERR
  FLOWAI_TEST_COMBINED="$(cat "$out" "$err")"
  export FLOWAI_TEST_COMBINED
  rm -f "$out" "$err"
  flowai_test_assert_rc 0 "UC-CLI-030" || return
  flowai_test_assert_combined_contains "$ver" "UC-CLI-030" || return

  out="$(mktemp)"
  err="$(mktemp)"
  set +e
  (cd "$FLOWAI_HOME" && FLOWAI_TESTING=1 ./bin/fai help) >"$out" 2>"$err"
  rc=$?
  set -e
  export FLOWAI_TEST_RC=$rc
  FLOWAI_TEST_COMBINED="$(cat "$out" "$err")"
  export FLOWAI_TEST_COMBINED
  rm -f "$out" "$err"
  flowai_test_assert_rc 0 "UC-CLI-030" || return
  flowai_test_assert_combined_contains "short for flowai" "UC-CLI-030" || return

  flowai_test_pass "UC-CLI-030" "fai is an alias for flowai (version + help banner)"
}

# UC-CLI-038 / tests/usecases/038-cli-config-help.md
flowai_test_s_cli_038() {
  flowai_test_invoke config --help
  flowai_test_assert_rc 0 "UC-CLI-038" || return
  flowai_test_assert_combined_contains "Usage: flowai validate" "UC-CLI-038" || return
  flowai_test_assert_combined_contains "(same as: flowai config validate)" "UC-CLI-038" || return
  flowai_test_pass "UC-CLI-038" "flowai config --help exits 0 and shows usage"
}

# UC-CLI-039 / tests/usecases/039-cli-config-unknown.md
flowai_test_s_cli_039() {
  flowai_test_invoke config definitely-unknown-cmd
  flowai_test_assert_rc 1 "UC-CLI-039" || return
  flowai_test_assert_combined_contains "Unknown config subcommand" "UC-CLI-039" || return
  flowai_test_pass "UC-CLI-039" "flowai config <unknown> exits 1 with error"
}

# UC-CLI-040 / tests/usecases/040-cli-update-help.md
flowai_test_s_cli_040() {
  flowai_test_invoke update --help
  flowai_test_assert_rc 0 "UC-CLI-040" || return
  flowai_test_assert_combined_contains "Self-update FlowAI" "UC-CLI-040" || return
  flowai_test_assert_combined_contains "Usage:" "UC-CLI-040" || return
  flowai_test_pass "UC-CLI-040" "flowai update --help exits 0 and shows usage"
}
