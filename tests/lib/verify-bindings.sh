#!/usr/bin/env bash
# Ensures tests/usecases/*.md automated_test: lines map to real functions in tests/cases/*.sh
# Quiet on success; stderr on failure. Set FLOWAI_TEST_VERBOSE=1 for a one-line summary.
# shellcheck shell=bash

flowai_verify_usecase_bindings() {
  local tests_root="${1:-}"
  if [[ -z "$tests_root" ]]; then
    tests_root="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  fi

  local usecases_dir="$tests_root/usecases"
  local err=0
  local count=0

  shopt -s nullglob
  for f in "$usecases_dir"/[0-9][0-9][0-9]-*.md; do
    [[ -f "$f" ]] || continue

    local fn
    fn="$(grep -m1 '^automated_test:' "$f" 2>/dev/null | sed 's/^automated_test:[[:space:]]*//;s/[[:space:]]*$//' || true)"
    if [[ -z "$fn" ]]; then
      continue
    fi

    local hit=0
    for c in "$tests_root/cases/"*.sh; do
      [[ -f "$c" ]] || continue
      if grep -q "^${fn}()" "$c" 2>/dev/null; then
        hit=1
        break
      fi
    done
    count=$((count + 1))
    if [[ "$hit" -eq 0 ]]; then
      printf 'FAIL: %s declares automated_test=%s but no %s() in tests/cases/\n' "${f##*/}" "$fn" "$fn" >&2
      err=$((err + 1))
    fi
  done
  shopt -u nullglob

  if [[ "$err" -gt 0 ]]; then
    return 1
  fi

  if [[ "${FLOWAI_TEST_VERBOSE:-}" == "1" ]]; then
    printf 'Bindings: %s use case(s) wired to test functions.\n' "$count"
  fi
  return 0
}
