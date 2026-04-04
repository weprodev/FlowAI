#!/usr/bin/env bash
# Only checks use case ↔ test wiring (verbose). Full suite: make test / make verify
# shellcheck shell=bash
set -euo pipefail
TESTS_ROOT="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/verify-bindings.sh
source "$TESTS_ROOT/lib/verify-bindings.sh"
export FLOWAI_TEST_VERBOSE=1
flowai_verify_usecase_bindings "$TESTS_ROOT"
