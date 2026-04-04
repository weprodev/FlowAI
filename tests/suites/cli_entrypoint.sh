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
  flowai_test_pass "UC-CLI-001" "flowai with no args prints usage and exits 1"
}

# UC-CLI-002 / tests/usecases/002-cli-help-command.md
flowai_test_s_cli_002() {
  flowai_test_invoke help
  flowai_test_assert_rc 0 "UC-CLI-002" || return
  flowai_test_assert_combined_contains "Usage" "UC-CLI-002" || return
  flowai_test_pass "UC-CLI-002" "flowai help exits 0 and shows usage"
}

# UC-CLI-003 / tests/usecases/003-cli-help-short-flag.md
flowai_test_s_cli_003() {
  flowai_test_invoke -h
  flowai_test_assert_rc 0 "UC-CLI-003" || return
  flowai_test_assert_combined_contains "FlowAI" "UC-CLI-003" || return
  flowai_test_pass "UC-CLI-003" "flowai -h exits 0 and shows usage"
}

# UC-CLI-007 / tests/usecases/007-cli-help-long-flag.md
flowai_test_s_cli_007() {
  flowai_test_invoke --help
  flowai_test_assert_rc 0 "UC-CLI-007" || return
  flowai_test_assert_combined_contains "FlowAI" "UC-CLI-007" || return
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
