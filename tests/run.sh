#!/usr/bin/env bash
# FlowAI test runner — use case bindings + harness (single entry; bindings are silent on success).
# Usage: ./tests/run.sh
# Verbose bindings: FLOWAI_TEST_VERBOSE=1 ./tests/run.sh
# shellcheck shell=bash

set -euo pipefail

TESTS_ROOT="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(CDPATH="" cd "$TESTS_ROOT/.." && pwd)"
# bin/fai → bin/flowai for harness only (install.sh creates the same symlink under the install prefix).
( cd "$REPO_ROOT/bin" && ln -sf flowai fai )
export FLOWAI_HOME="$REPO_ROOT"
export FLOWAI_TESTING=1

# shellcheck source=tests/lib/verify-bindings.sh
source "$TESTS_ROOT/lib/verify-bindings.sh"
if ! flowai_verify_usecase_bindings "$TESTS_ROOT"; then
  exit 1
fi

# shellcheck source=tests/lib/harness.sh
source "$TESTS_ROOT/lib/harness.sh"
# shellcheck source=tests/suites/cli_entrypoint.sh
source "$TESTS_ROOT/suites/cli_entrypoint.sh"
# shellcheck source=tests/suites/lifecycle_happy.sh
source "$TESTS_ROOT/suites/lifecycle_happy.sh"
# shellcheck source=tests/suites/skill_local_path.sh
source "$TESTS_ROOT/suites/skill_local_path.sh"
# shellcheck source=tests/suites/role_override.sh
source "$TESTS_ROOT/suites/role_override.sh"
# shellcheck source=tests/suites/graph_knowledge.sh
source "$TESTS_ROOT/suites/graph_knowledge.sh"

echo "FlowAI test run — FLOWAI_HOME=$FLOWAI_HOME"
echo ""

set +e
flowai_test_s_cli_001
flowai_test_s_cli_002
flowai_test_s_cli_003
flowai_test_s_cli_004
flowai_test_s_cli_005
flowai_test_s_cli_006
flowai_test_s_cli_007
flowai_test_s_cli_008
flowai_test_s_cli_009
flowai_test_s_cli_010
flowai_test_s_cli_011
flowai_test_s_cli_012
flowai_test_s_cli_013
flowai_test_s_cli_014
flowai_test_s_cli_015
flowai_test_s_cli_016
flowai_test_s_cli_017
flowai_test_s_cli_018
flowai_test_s_cli_019
flowai_test_s_cli_020
flowai_test_s_cli_021
flowai_test_s_cli_022
flowai_test_s_cli_023
flowai_test_s_cli_024
flowai_test_s_cli_025
flowai_test_s_cli_026
flowai_test_s_cli_027
flowai_test_s_cli_028
flowai_test_s_cli_029
flowai_test_s_cli_030
flowai_test_s_cli_031
flowai_test_s_cli_032
flowai_test_s_cli_033
flowai_test_s_cli_034
flowai_test_s_cli_035
flowai_test_s_cli_036
flowai_test_s_cli_037
# skill local path
flowai_test_s_skl_001
flowai_test_s_skl_002
flowai_test_s_skl_003
flowai_test_s_skl_004
flowai_test_s_skl_005
flowai_test_s_skl_006
flowai_test_s_skl_007
flowai_test_s_skl_008
# role override resolution
flowai_test_s_role_001
flowai_test_s_role_002
flowai_test_s_role_003
flowai_test_s_role_004
flowai_test_s_role_005
flowai_test_s_role_006
flowai_test_s_role_007
flowai_test_s_role_008
flowai_test_s_role_009
# knowledge graph & wiki
flowai_test_s_graph_001
flowai_test_s_graph_002
flowai_test_s_graph_003
flowai_test_s_graph_004
flowai_test_s_graph_005
flowai_test_s_graph_006
flowai_test_s_graph_007
flowai_test_s_graph_008
flowai_test_s_graph_009
flowai_test_s_graph_010
flowai_test_s_graph_011
flowai_test_s_graph_012
flowai_test_s_graph_013
flowai_test_s_graph_014
flowai_test_s_graph_015
flowai_test_s_graph_016
flowai_test_s_graph_017
flowai_test_s_graph_018
flowai_test_s_graph_019
flowai_test_s_graph_020
# phase 1+2: chronicle, frontmatter, lint
flowai_test_s_graph_021
flowai_test_s_graph_022
flowai_test_s_graph_023
flowai_test_s_graph_024
flowai_test_s_graph_025
flowai_test_s_graph_026
flowai_test_s_graph_027
flowai_test_s_graph_028
flowai_test_s_graph_029
flowai_test_s_graph_030
flowai_test_s_graph_031
set -e

if [[ "${FLOWAI_TEST_FAILURES:-0}" -gt 0 ]]; then
  echo ""
  printf '%s\n' "FAILED: ${FLOWAI_TEST_FAILURES} assertion(s)" >&2
  exit 1
fi

echo ""
echo "All tests passed."
