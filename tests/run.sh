#!/usr/bin/env bash
# FlowAI test runner — use case bindings + harness (single entry; bindings are silent on success).
# Usage: ./tests/run.sh
# Verbose bindings: FLOWAI_TEST_VERBOSE=1 ./tests/run.sh
# shellcheck shell=bash

set -euo pipefail

TESTS_ROOT="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(CDPATH="" cd "$TESTS_ROOT/.." && pwd)"
export FLOWAI_HOME="$REPO_ROOT"

# shellcheck source=lib/verify-bindings.sh
source "$TESTS_ROOT/lib/verify-bindings.sh"
if ! flowai_verify_usecase_bindings "$TESTS_ROOT"; then
  exit 1
fi

# shellcheck source=lib/harness.sh
source "$TESTS_ROOT/lib/harness.sh"
# shellcheck source=cases/cli_entrypoint.sh
source "$TESTS_ROOT/cases/cli_entrypoint.sh"
# shellcheck source=cases/lifecycle_happy.sh
source "$TESTS_ROOT/cases/lifecycle_happy.sh"

echo "FlowAI test run — FLOWAI_HOME=$FLOWAI_HOME"
echo ""

set +e
flowai_test_s_cli_001
flowai_test_s_cli_002
flowai_test_s_cli_003
flowai_test_s_cli_007
flowai_test_s_cli_008
flowai_test_s_cli_004
flowai_test_s_cli_005
flowai_test_s_cli_006
flowai_test_s_cli_009
flowai_test_s_cli_010
flowai_test_s_cli_016
flowai_test_s_cli_017
flowai_test_s_cli_018
flowai_test_s_cli_022
flowai_test_s_cli_011
flowai_test_s_cli_012
flowai_test_s_cli_021
flowai_test_s_cli_013
flowai_test_s_cli_020
flowai_test_s_cli_014
flowai_test_s_cli_015
flowai_test_s_cli_019
set -e

if [[ "${FLOWAI_TEST_FAILURES:-0}" -gt 0 ]]; then
  echo ""
  printf '%s\n' "FAILED: ${FLOWAI_TEST_FAILURES} assertion(s)" >&2
  exit 1
fi

echo ""
echo "All tests passed."
