#!/usr/bin/env bash
# Same as `make test` / `make verify` — deterministic only. For AI review, use run-ai-smoke.sh or `make verify-ai`.
# shellcheck shell=bash
set -euo pipefail
REPO_ROOT="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec bash "$REPO_ROOT/tests/run.sh"
