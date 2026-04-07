#!/usr/bin/env bash
# Lifecycle “happy path” smoke tests — temp dirs, optional jq/tmux.
# Expects tests/lib/harness.sh sourced first (see tests/run.sh).
# shellcheck shell=bash

# UC-CLI-010 / tests/usecases/010-cli-init-happy.md
flowai_test_s_cli_010() {
  if ! command -v jq >/dev/null 2>&1; then
    printf 'ok  %s — %s (skipped: jq not installed)\n' "UC-CLI-010" "flowai init creates project layout"
    return 0
  fi
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  flowai_test_invoke_in_dir "$tmp" init
  flowai_test_assert_rc 0 "UC-CLI-010" || return
  flowai_test_assert_path_exists "$tmp/.flowai/config.json" "UC-CLI-010" || return
  flowai_test_assert_path_exists "$tmp/specs" "UC-CLI-010" || return
  flowai_test_pass "UC-CLI-010" "flowai init creates .flowai/config.json and specs/"
}

# UC-CLI-016 / tests/usecases/016-cli-init-idempotent.md
flowai_test_s_cli_016() {
  if ! command -v jq >/dev/null 2>&1; then
    printf 'ok  %s — %s (skipped: jq not installed)\n' "UC-CLI-016" "flowai init idempotent"
    return 0
  fi
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  flowai_test_invoke_in_dir "$tmp" init
  flowai_test_assert_rc 0 "UC-CLI-016" || return

  jq '. + {"_flowai_test_idempotency": "preserve"}' "$tmp/.flowai/config.json" >"$tmp/.flowai/config.json.tmp"
  mv "$tmp/.flowai/config.json.tmp" "$tmp/.flowai/config.json"

  flowai_test_invoke_in_dir "$tmp" init
  flowai_test_assert_rc 0 "UC-CLI-016" || return
  flowai_test_assert_combined_contains "already exists" "UC-CLI-016" || return
  flowai_test_assert_combined_contains "leaving config" "UC-CLI-016" || return

  if [[ "$(jq -r '._flowai_test_idempotency // empty' "$tmp/.flowai/config.json")" != "preserve" ]]; then
    printf 'FAIL UC-CLI-016: sentinel key missing from config after second init\n' >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    return 1
  fi

  flowai_test_pass "UC-CLI-016" "second flowai init preserves config and exits 0"
}

# UC-CLI-017 / tests/usecases/017-cli-missing-dependencies.md
flowai_test_s_cli_017() {
  local tmp fake_root bash_only jqbin tmuxbin gumdir path_no_gum
  tmp="$(mktemp -d)"
  fake_root="$(flowai_test_mktemp_fake_bash_only_root)"
  bash_only="$fake_root/bin"
  trap 'rm -rf "$tmp" "$fake_root"' RETURN

  flowai_test_invoke_in_dir_env "$tmp" PATH="$bash_only" "$FLOWAI_BIN" init
  flowai_test_assert_rc 1 "UC-CLI-017" || return
  flowai_test_assert_combined_contains "jq is required" "UC-CLI-017" || return

  flowai_test_invoke_in_dir_env "$tmp" PATH="$bash_only" "$FLOWAI_BIN" status
  flowai_test_assert_rc 1 "UC-CLI-017" || return
  flowai_test_assert_combined_contains "tmux is not installed" "UC-CLI-017" || return

  flowai_test_invoke_in_dir "$tmp" init
  flowai_test_assert_rc 0 "UC-CLI-017" || return

  jqbin="$(dirname "$(command -v jq)")"
  tmuxbin="$(dirname "$(command -v tmux)")"
  gumdir=""
  if command -v gum >/dev/null 2>&1; then
    gumdir="$(dirname "$(command -v gum)")"
  fi

  if [[ -z "$gumdir" ]]; then
    flowai_test_pass "UC-CLI-017" "missing jq/tmux errors; gum not on PATH (skip gum subtest)"
    return 0
  fi
  if [[ "$gumdir" == "$jqbin" || "$gumdir" == "$tmuxbin" ]]; then
    flowai_test_pass "UC-CLI-017" "missing jq/tmux errors; gum shares install dir (skip gum subtest)"
    return 0
  fi

  path_no_gum="$bash_only:$jqbin:$tmuxbin"
  flowai_test_invoke_in_dir_env "$tmp" PATH="$path_no_gum" "$FLOWAI_BIN" start
  flowai_test_assert_rc 1 "UC-CLI-017" || return
  flowai_test_assert_combined_contains "gum is required" "UC-CLI-017" || return

  flowai_test_pass "UC-CLI-017" "missing jq/tmux/gum produce clear log_error messages"
}

# UC-CLI-018 / tests/usecases/018-cli-invalid-config-json.md
flowai_test_s_cli_018() {
  if ! command -v jq >/dev/null 2>&1; then
    printf 'ok  %s — %s (skipped: jq not installed)\n' "UC-CLI-018" "invalid config.json rejected"
    return 0
  fi
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  flowai_test_invoke_in_dir "$tmp" init
  flowai_test_assert_rc 0 "UC-CLI-018" || return

  printf '{ not valid json' >"$tmp/.flowai/config.json"

  flowai_test_invoke_in_dir "$tmp" init
  flowai_test_assert_rc 1 "UC-CLI-018" || return
  flowai_test_assert_combined_contains "Invalid JSON" "UC-CLI-018" || return

  flowai_test_invoke_in_dir "$tmp" start --headless
  flowai_test_assert_rc 1 "UC-CLI-018" || return
  flowai_test_assert_combined_contains "Invalid JSON" "UC-CLI-018" || return

  flowai_test_pass "UC-CLI-018" "invalid .flowai/config.json fails init and start with clear error"
}

# UC-CLI-022 / tests/usecases/022-cli-not-initialized.md
flowai_test_s_cli_022() {
  if ! command -v jq >/dev/null 2>&1 || ! command -v tmux >/dev/null 2>&1; then
    printf 'ok  %s — %s (skipped: jq or tmux not installed)\n' "UC-CLI-022" "start/run without init"
    return 0
  fi
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  flowai_test_invoke_in_dir "$tmp" start --headless
  flowai_test_assert_rc 1 "UC-CLI-022" || return
  flowai_test_assert_combined_contains "Not a FlowAI project here" "UC-CLI-022" || return
  flowai_test_assert_combined_contains "flowai init" "UC-CLI-022" || return

  flowai_test_invoke_in_dir "$tmp" run plan
  flowai_test_assert_rc 1 "UC-CLI-022" || return
  flowai_test_assert_combined_contains "Not a FlowAI project here" "UC-CLI-022" || return

  flowai_test_pass "UC-CLI-022" "start and run fail with Not a FlowAI project when never initialized"
}

# UC-CLI-011 / tests/usecases/011-cli-status-no-session.md
flowai_test_s_cli_011() {
  if ! command -v tmux >/dev/null 2>&1; then
    printf 'ok  %s — %s (skipped: tmux not installed)\n' "UC-CLI-011" "flowai status when no session"
    return 0
  fi
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  # status works even without a config — just needs tmux absent or session absent
  flowai_test_invoke_in_dir "$tmp" status
  flowai_test_assert_rc 0 "UC-CLI-011" || return
  flowai_test_assert_combined_contains "not running" "UC-CLI-011" || return
  flowai_test_pass "UC-CLI-011" "flowai status exits 0 when session is absent"
}

# UC-CLI-012 / tests/usecases/012-cli-kill-no-session.md
flowai_test_s_cli_012() {
  if ! command -v tmux >/dev/null 2>&1; then
    printf 'ok  %s — %s (skipped: tmux not installed)\n' "UC-CLI-012" "flowai kill when no session"
    return 0
  fi
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  flowai_test_invoke_in_dir "$tmp" kill
  flowai_test_assert_rc 0 "UC-CLI-012" || return
  flowai_test_assert_combined_contains "No active" "UC-CLI-012" || return
  flowai_test_pass "UC-CLI-012" "flowai kill exits 0 when no session to kill"
}

# UC-CLI-021 / tests/usecases/021-cli-stop-alias.md
flowai_test_s_cli_021() {
  if ! command -v tmux >/dev/null 2>&1; then
    printf 'ok  %s — %s (skipped: tmux not installed)\n' "UC-CLI-021" "flowai stop when no session"
    return 0
  fi
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  flowai_test_invoke_in_dir "$tmp" stop
  flowai_test_assert_rc 0 "UC-CLI-021" || return
  flowai_test_assert_combined_contains "No active" "UC-CLI-021" || return
  flowai_test_pass "UC-CLI-021" "flowai stop exits 0 when no session (alias of kill)"
}

# UC-CLI-013 / tests/usecases/013-cli-run-plan-contract.md
flowai_test_s_cli_013() {
  if ! command -v jq >/dev/null 2>&1; then
    printf 'ok  %s — %s (skipped: jq not installed)\n' "UC-CLI-013" "flowai run plan contract"
    return 0
  fi
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  flowai_test_invoke_in_dir "$tmp" init
  flowai_test_assert_rc 0 "UC-CLI-013" || return

  mkdir -p "$tmp/specs/feat-contract"
  printf 'ok\n' >"$tmp/specs/feat-contract/spec.md"
  mkdir -p "$tmp/.flowai/signals"
  touch "$tmp/.flowai/signals/spec.ready"

  flowai_test_invoke_in_dir_env "$tmp" FLOWAI_TEST_SKIP_AI=1 "$FLOWAI_BIN" run plan
  flowai_test_assert_rc 0 "UC-CLI-013" || return
  flowai_test_assert_combined_contains "contract test" "UC-CLI-013" || return
  flowai_test_pass "UC-CLI-013" "flowai run plan contract (SKIP_AI) exits 0 after fixture"
}

# UC-CLI-020 / tests/usecases/020-cli-run-implement-contract.md
flowai_test_s_cli_020() {
  if ! command -v jq >/dev/null 2>&1; then
    printf 'ok  %s — %s (skipped: jq not installed)\n' "UC-CLI-020" "flowai run implement contract"
    return 0
  fi
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  flowai_test_invoke_in_dir "$tmp" init
  flowai_test_assert_rc 0 "UC-CLI-020" || return

  mkdir -p "$tmp/specs/feat-impl"
  printf 'ok\n' >"$tmp/specs/feat-impl/spec.md"
  printf 'ok\n' >"$tmp/specs/feat-impl/tasks.md"
  mkdir -p "$tmp/.flowai/signals"
  touch "$tmp/.flowai/signals/tasks.ready"

  flowai_test_invoke_in_dir_env "$tmp" FLOWAI_TEST_SKIP_AI=1 "$FLOWAI_BIN" run implement
  flowai_test_assert_rc 0 "UC-CLI-020" || return
  flowai_test_assert_combined_contains "contract test" "UC-CLI-020" || return

  flowai_test_pass "UC-CLI-020" "flowai run implement contract (SKIP_AI) exits 0 after fixture"
}

# UC-CLI-014 / tests/usecases/014-cli-start-manual.md — headless creates a real tmux session (no attach)
flowai_test_s_cli_014() {
  if ! command -v jq >/dev/null 2>&1 || ! command -v tmux >/dev/null 2>&1; then
    printf 'ok  %s — %s (skipped: jq or tmux not installed)\n' "UC-CLI-014" "flowai start --headless creates session"
    return 0
  fi

  local tmp sess
  tmp="$(mktemp -d)"
  tmp="$(cd "$tmp" && pwd)"
  sess="$(FLOWAI_HOME="$FLOWAI_HOME" bash -c 'source "$FLOWAI_HOME/src/core/session.sh"; flowai_session_name "$1"' _ "$tmp")"
  trap 'tmux kill-session -t "$sess" 2>/dev/null || true; rm -rf "$tmp"' RETURN

  flowai_test_invoke_in_dir "$tmp" init
  flowai_test_assert_rc 0 "UC-CLI-014" || return

  flowai_test_invoke_in_dir "$tmp" start --headless
  flowai_test_assert_rc 0 "UC-CLI-014" || return
  flowai_test_assert_combined_contains "Headless" "UC-CLI-014" || return

  if ! tmux has-session -t "$sess" 2>/dev/null; then
    printf 'FAIL UC-CLI-014: expected tmux session %q to exist\n' "$sess" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    return 1
  fi

  flowai_test_pass "UC-CLI-014" "flowai start --headless exits 0 and tmux session exists"
}

# UC-CLI-015 / tests/usecases/015-cli-session-lifecycle.md — start (headless) → status → kill → status
flowai_test_s_cli_015() {
  if ! command -v jq >/dev/null 2>&1 || ! command -v tmux >/dev/null 2>&1; then
    printf 'ok  %s — %s (skipped: jq or tmux not installed)\n' "UC-CLI-015" "session lifecycle start/status/kill"
    return 0
  fi

  local tmp sess
  tmp="$(mktemp -d)"
  tmp="$(cd "$tmp" && pwd)"
  sess="$(FLOWAI_HOME="$FLOWAI_HOME" bash -c 'source "$FLOWAI_HOME/src/core/session.sh"; flowai_session_name "$1"' _ "$tmp")"
  trap 'tmux kill-session -t "$sess" 2>/dev/null || true; rm -rf "$tmp"' RETURN

  flowai_test_invoke_in_dir "$tmp" init
  flowai_test_assert_rc 0 "UC-CLI-015" || return

  flowai_test_invoke_in_dir "$tmp" start --headless
  flowai_test_assert_rc 0 "UC-CLI-015" || return
  if ! tmux has-session -t "$sess" 2>/dev/null; then
    printf 'FAIL UC-CLI-015: expected tmux session %q after start --headless\n' "$sess" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    return 1
  fi

  flowai_test_invoke_in_dir "$tmp" status
  flowai_test_assert_rc 0 "UC-CLI-015" || return
  flowai_test_assert_combined_contains "FlowAI" "UC-CLI-015" || return
  flowai_test_assert_combined_contains "running" "UC-CLI-015" || return
  flowai_test_assert_combined_not_contains "not running" "UC-CLI-015" || return

  flowai_test_invoke_in_dir "$tmp" kill
  flowai_test_assert_rc 0 "UC-CLI-015" || return
  flowai_test_assert_combined_contains "killed" "UC-CLI-015" || return

  if tmux has-session -t "$sess" 2>/dev/null; then
    printf 'FAIL UC-CLI-015: session %q should be gone after kill\n' "$sess" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    return 1
  fi

  flowai_test_invoke_in_dir "$tmp" status
  flowai_test_assert_rc 0 "UC-CLI-015" || return
  flowai_test_assert_combined_contains "not running" "UC-CLI-015" || return

  flowai_test_pass "UC-CLI-015" "start --headless then status/kill/status matches running then idle"
}

# UC-CLI-019 / tests/usecases/019-cli-start-session-already-running.md
flowai_test_s_cli_019() {
  if ! command -v jq >/dev/null 2>&1 || ! command -v tmux >/dev/null 2>&1; then
    printf 'ok  %s — %s (skipped: jq or tmux not installed)\n' "UC-CLI-019" "start --headless when session exists"
    return 0
  fi
  local tmp sess
  tmp="$(mktemp -d)"
  tmp="$(cd "$tmp" && pwd)"
  sess="$(FLOWAI_HOME="$FLOWAI_HOME" bash -c 'source "$FLOWAI_HOME/src/core/session.sh"; flowai_session_name "$1"' _ "$tmp")"
  trap 'tmux kill-session -t "$sess" 2>/dev/null || true; rm -rf "$tmp"' RETURN

  flowai_test_invoke_in_dir "$tmp" init
  flowai_test_assert_rc 0 "UC-CLI-019" || return

  flowai_test_invoke_in_dir "$tmp" start --headless
  flowai_test_assert_rc 0 "UC-CLI-019" || return

  flowai_test_invoke_in_dir "$tmp" start --headless
  flowai_test_assert_rc 0 "UC-CLI-019" || return
  flowai_test_assert_combined_contains "already running" "UC-CLI-019" || return
  flowai_test_assert_combined_contains "Headless" "UC-CLI-019" || return

  flowai_test_pass "UC-CLI-019" "second start --headless exits 0 when session already running"
}

# UC-CLI-023 / tests/usecases/023-cli-skills-phase-to-role.md
flowai_test_s_cli_023() {
  if ! command -v jq >/dev/null 2>&1; then
    printf 'ok  %s — %s (skipped: jq not installed)\n' "UC-CLI-023" "skills phase maps to pipeline role"
    return 0
  fi
  local tmp eff match
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  flowai_test_invoke_in_dir "$tmp" init
  flowai_test_assert_rc 0 "UC-CLI-023" || return

  # shellcheck disable=SC2016
  eff="$(env FLOWAI_HOME="$FLOWAI_HOME" "FLOWAI_DIR=$tmp/.flowai" bash -c '
    source "$FLOWAI_HOME/src/core/skills.sh"
    flowai_skills_effective_role_for_phase plan
  ')"
  if [[ "$eff" != "team-lead" ]]; then
    printf 'FAIL UC-CLI-023: plan phase should map to team-lead, got %q\n' "$eff" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    return 1
  fi

  # shellcheck disable=SC2016
  eff="$(env FLOWAI_HOME="$FLOWAI_HOME" "FLOWAI_DIR=$tmp/.flowai" bash -c '
    source "$FLOWAI_HOME/src/core/skills.sh"
    flowai_skills_effective_role_for_phase impl
  ')"
  if [[ "$eff" != "backend-engineer" ]]; then
    printf 'FAIL UC-CLI-023: impl phase should map to backend-engineer, got %q\n' "$eff" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    return 1
  fi

  # shellcheck disable=SC2016
  match="$(env FLOWAI_HOME="$FLOWAI_HOME" "FLOWAI_DIR=$tmp/.flowai" bash -c '
    source "$FLOWAI_HOME/src/core/skills.sh"
    flowai_skills_list_for_role team-lead
  ' | grep -c '^writing-plans$' || true)"
  if [[ "$match" -lt 1 ]]; then
    printf 'FAIL UC-CLI-023: team-lead skills should include writing-plans\n' >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    return 1
  fi

  flowai_test_pass "UC-CLI-023" "pipeline phase resolves to role; skills list matches config defaults"
}

# UC-CLI-024 / tests/usecases/024-cli-mcp-minimal-json.md
flowai_test_s_cli_024() {
  if ! command -v jq >/dev/null 2>&1; then
    printf 'ok  %s — %s (skipped: jq not installed)\n' "UC-CLI-024" "mcp list seeds minimal mcp.json"
    return 0
  fi
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  flowai_test_invoke_in_dir "$tmp" init
  flowai_test_assert_rc 0 "UC-CLI-024" || return

  flowai_test_invoke_in_dir "$tmp" mcp list
  flowai_test_assert_rc 0 "UC-CLI-024" || return
  flowai_test_assert_path_exists "$tmp/.flowai/mcp.json" "UC-CLI-024" || return

  if ! jq -e '.mcpServers.context7.command == "npx" and (.mcpServers.context7.args | length) > 0' "$tmp/.flowai/mcp.json" >/dev/null 2>&1; then
    printf 'FAIL UC-CLI-024: mcp.json missing minimal context7 server\n' >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    return 1
  fi

  if jq -e 'has("mcpServers") and .mcpServers.context7 | has("description")' "$tmp/.flowai/mcp.json" >/dev/null 2>&1; then
    printf 'FAIL UC-CLI-024: mcp.json should omit description for Claude runtime file\n' >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    return 1
  fi

  flowai_test_pass "UC-CLI-024" "flowai mcp list creates minimal mcp.json from config"
}
