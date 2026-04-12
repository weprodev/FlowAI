#!/usr/bin/env bash
# Lifecycle “happy path” smoke tests — temp dirs, optional jq/tmux.
# Expects tests/lib/harness.sh sourced first (see tests/run.sh).
# shellcheck shell=bash

# UC-CLI-010 / tests/usecases/010-cli-init-happy.md
flowai_test_s_cli_010() {
  if flowai_test_skip_if_missing_jq "UC-CLI-010" "flowai init creates project layout"; then return 0; fi
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
  if flowai_test_skip_if_missing_jq "UC-CLI-016" "flowai init idempotent"; then return 0; fi
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

  if [[ "$(jq -r '._flowai_test_idempotency // empty' "$tmp/.flowai/config.json" | tr -d '\r')" != "preserve" ]]; then
    printf 'FAIL UC-CLI-016: sentinel key missing from config after second init\n' >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    return 1
  fi

  flowai_test_pass "UC-CLI-016" "second flowai init preserves config and exits 0"
}

# UC-CLI-017 / tests/usecases/017-cli-missing-dependencies.md
flowai_test_s_cli_017() {
  # Skip on Windows — symlinked bash can't resolve shared libraries in MSYS/Git Bash
  if [[ "$(uname -s 2>/dev/null)" == MINGW* || "$(uname -s 2>/dev/null)" == MSYS* ]]; then
    flowai_test_pass "UC-CLI-017" "missing dependency errors (skipped: Windows symlink limitation)"
    return 0
  fi
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
  if flowai_test_skip_if_missing_jq "UC-CLI-018" "invalid config.json rejected"; then return 0; fi
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  flowai_test_invoke_in_dir "$tmp" init
  flowai_test_assert_rc 0 "UC-CLI-018" || return

  printf '{ not valid json' >"$tmp/.flowai/config.json"

  flowai_test_invoke_in_dir "$tmp" init
  flowai_test_assert_rc 1 "UC-CLI-018" || return
  flowai_test_assert_combined_contains "Invalid JSON" "UC-CLI-018" || return

  # flowai start requires tmux — only assert the JSON check when tmux is present
  if command -v tmux >/dev/null 2>&1; then
    flowai_test_invoke_in_dir "$tmp" start --headless
    flowai_test_assert_rc 1 "UC-CLI-018" || return
    flowai_test_assert_combined_contains "Invalid JSON" "UC-CLI-018" || return
  fi

  flowai_test_pass "UC-CLI-018" "invalid .flowai/config.json fails init (and start when tmux present) with clear error"
}

# UC-CLI-022 / tests/usecases/022-cli-not-initialized.md
flowai_test_s_cli_022() {
  if flowai_test_skip_if_missing_jq "UC-CLI-022" "start/run without init"; then return 0; fi
  if flowai_test_skip_if_missing_tmux "UC-CLI-022" "start/run without init"; then return 0; fi
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
  if flowai_test_skip_if_missing_tmux "UC-CLI-011" "flowai status when no session"; then return 0; fi
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
  if flowai_test_skip_if_missing_tmux "UC-CLI-012" "flowai kill when no session"; then return 0; fi
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
  if flowai_test_skip_if_missing_tmux "UC-CLI-021" "flowai stop when no session"; then return 0; fi
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
  if flowai_test_skip_if_missing_jq "UC-CLI-013" "flowai run plan contract"; then return 0; fi
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
  if flowai_test_skip_if_missing_jq "UC-CLI-020" "flowai run implement contract"; then return 0; fi
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
  if flowai_test_skip_if_missing_jq "UC-CLI-014" "flowai start --headless creates session"; then return 0; fi
  if flowai_test_skip_if_missing_tmux "UC-CLI-014" "flowai start --headless creates session"; then return 0; fi

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
  if flowai_test_skip_if_missing_jq "UC-CLI-015" "session lifecycle start/status/kill"; then return 0; fi
  if flowai_test_skip_if_missing_tmux "UC-CLI-015" "session lifecycle start/status/kill"; then return 0; fi

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
  if flowai_test_skip_if_missing_jq "UC-CLI-019" "start --headless when session exists"; then return 0; fi
  if flowai_test_skip_if_missing_tmux "UC-CLI-019" "start --headless when session exists"; then return 0; fi
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
  if flowai_test_skip_if_missing_jq "UC-CLI-023" "skills phase maps to pipeline role"; then return 0; fi
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
  if flowai_test_skip_if_missing_jq "UC-CLI-024" "mcp list seeds minimal mcp.json"; then return 0; fi
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


# UC-CLI-026 / tests/usecases/026-cli-models-catalog-validation.md
flowai_test_s_cli_026() {
  local tmp out
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/.flowai"
  printf '{}\n' >"$tmp/.flowai/config.json"
  # shellcheck disable=SC2016
  out="$(env FLOWAI_HOME="$FLOWAI_HOME" "FLOWAI_DIR=$tmp/.flowai" bash -c '
    source "$FLOWAI_HOME/src/core/config.sh"
    source "$FLOWAI_HOME/src/core/ai.sh"
    flowai_ai_resolve_model_for_tool gemini "not-a-real-model-xyz"
  ' 2>/dev/null)"
  if [[ "$out" != *"gemini-2.5-pro"* ]]; then
    printf 'FAIL UC-CLI-026: expected catalog fallback gemini-2.5-pro in stdout, got %q\n' "$out" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    return 1
  fi
  flowai_test_pass "UC-CLI-026" "unknown gemini model id falls back to catalog default"
}

# UC-CLI-028 / tests/usecases/028-cli-config-validate-invalid-model.md
flowai_test_s_cli_028() {
  if flowai_test_skip_if_missing_jq "UC-CLI-028" "validate rejects bad model"; then return 0; fi
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  flowai_test_invoke_in_dir "$tmp" init
  flowai_test_assert_rc 0 "UC-CLI-028" || return

  jq '.roles["backend-engineer"].model = "___invalid_model_not_in_catalog___"' "$tmp/.flowai/config.json" >"$tmp/.flowai/config.json.new"
  mv "$tmp/.flowai/config.json.new" "$tmp/.flowai/config.json"

  flowai_test_invoke_in_dir "$tmp" validate
  flowai_test_assert_rc 1 "UC-CLI-028" || return
  flowai_test_assert_combined_contains "Invalid model" "UC-CLI-028" || return
  flowai_test_assert_combined_contains "models list" "UC-CLI-028" || return

  flowai_test_pass "UC-CLI-028" "flowai validate exits 1 when role model not in catalog"
}

# UC-CLI-029 / tests/usecases/029-cli-start-validates-models.md
flowai_test_s_cli_029() {
  if flowai_test_skip_if_missing_jq "UC-CLI-029" "start fails when config models invalid"; then return 0; fi
  if flowai_test_skip_if_missing_tmux "UC-CLI-029" "start fails when config models invalid"; then return 0; fi
  local tmp
  tmp="$(mktemp -d)"
  tmp="$(cd "$tmp" && pwd)"
  trap 'rm -rf "$tmp"' RETURN

  flowai_test_invoke_in_dir "$tmp" init
  flowai_test_assert_rc 0 "UC-CLI-029" || return

  jq '.master.model = "___bad_master_model___"' "$tmp/.flowai/config.json" >"$tmp/.flowai/config.json.new"
  mv "$tmp/.flowai/config.json.new" "$tmp/.flowai/config.json"

  flowai_test_invoke_in_dir_env "$tmp" FLOWAI_HOME="$FLOWAI_HOME" FLOWAI_TESTING=0 "$FLOWAI_BIN" start --headless
  flowai_test_assert_rc 1 "UC-CLI-029" || return
  flowai_test_assert_combined_contains "Model validation failed" "UC-CLI-029" || return

  flowai_test_pass "UC-CLI-029" "flowai start --headless exits 1 when model ids fail catalog validation"
}

# UC-CLI-031 / tests/usecases/031-cli-models-list-help.md
# Guards: models.sh help path — was crashing with 'local' at file scope.
flowai_test_s_cli_031() {
  flowai_test_invoke models list -h
  flowai_test_assert_rc 0 "UC-CLI-031" || return
  flowai_test_assert_combined_contains "Usage" "UC-CLI-031" || return

  flowai_test_invoke models list --help
  flowai_test_assert_rc 0 "UC-CLI-031" || return

  flowai_test_invoke models list help
  flowai_test_assert_rc 0 "UC-CLI-031" || return

  flowai_test_pass "UC-CLI-031" "flowai models list -h/--help/help exits 0 and shows usage"
}

# UC-CLI-032 / tests/usecases/032-cli-models-list-unknown-tool.md
# Guards: models.sh unknown-tool error path — was crashing with 'local' at file scope.
flowai_test_s_cli_032() {
  flowai_test_invoke models list __not_a_real_tool_xyz__
  flowai_test_assert_rc 1 "UC-CLI-032" || return
  flowai_test_assert_combined_contains "Unknown" "UC-CLI-032" || return
  flowai_test_pass "UC-CLI-032" "flowai models list <unknown-tool> exits 1 with error"
}

# UC-CLI-033 / tests/usecases/033-cli-catalog-plugin-contract.md
# THE OCP GUARDIAN: every tool in models-catalog.json must have a plugin file
# that defines both flowai_tool_<name>_print_models() and flowai_tool_<name>_run().
# This test would have caught the copilot gap immediately.
# Adding a new tool and forgetting the plugin will fail here — not at runtime.
flowai_test_s_cli_033() {
  if flowai_test_skip_if_missing_jq "UC-CLI-033" "catalog-to-plugin OCP contract"; then return 0; fi

  local catalog="$FLOWAI_HOME/models-catalog.json"
  if [[ ! -f "$catalog" ]]; then
    printf 'FAIL UC-CLI-033: models-catalog.json not found at %q\n' "$catalog" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    return 1
  fi

  local err=0
  local tool_name
  while IFS= read -r tool_name; do
    [[ -z "$tool_name" ]] && continue

    local plugin_file="$FLOWAI_HOME/src/tools/${tool_name}.sh"

    # 1. Plugin file must exist
    if [[ ! -f "$plugin_file" ]]; then
      printf 'FAIL UC-CLI-033: tool %q in models-catalog.json has no src/tools/%s.sh\n' \
        "$tool_name" "$tool_name" >&2
      err=$((err + 1))
      continue
    fi

    # 2. flowai_tool_<name>_print_models() must be defined
    if ! grep -q "^flowai_tool_${tool_name}_print_models()" "$plugin_file" 2>/dev/null; then
      printf 'FAIL UC-CLI-033: src/tools/%s.sh missing flowai_tool_%s_print_models()\n' \
        "$tool_name" "$tool_name" >&2
      err=$((err + 1))
    fi

    # 3. flowai_tool_<name>_run() must be defined (the critical dispatcher contract)
    if ! grep -q "^flowai_tool_${tool_name}_run()" "$plugin_file" 2>/dev/null; then
      printf 'FAIL UC-CLI-033: src/tools/%s.sh missing flowai_tool_%s_run()\n' \
        "$tool_name" "$tool_name" >&2
      err=$((err + 1))
    fi

  done < <(jq -r '.tools | keys[]' "$catalog" 2>/dev/null | tr -d '\r')

  if [[ "$err" -gt 0 ]]; then
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    return 1
  fi

  flowai_test_pass "UC-CLI-033" "all catalog tools have src/tools/<name>.sh with _print_models() and _run()"
}

# UC-CLI-034 / tests/usecases/034-cli-run-review-contract.md
# Guards: review phase SKIP_AI guard (was missing) and approval loop contract.
flowai_test_s_cli_034() {
  if flowai_test_skip_if_missing_jq "UC-CLI-034" "flowai run review contract"; then return 0; fi
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  flowai_test_invoke_in_dir "$tmp" init
  flowai_test_assert_rc 0 "UC-CLI-034" || return

  mkdir -p "$tmp/specs/feat-review"
  printf 'ok\n' >"$tmp/specs/feat-review/spec.md"
  printf 'ok\n' >"$tmp/specs/feat-review/tasks.md"
  mkdir -p "$tmp/.flowai/signals"
  touch "$tmp/.flowai/signals/impl.ready"

  flowai_test_invoke_in_dir_env "$tmp" FLOWAI_TEST_SKIP_AI=1 "$FLOWAI_BIN" run review
  flowai_test_assert_rc 0 "UC-CLI-034" || return
  flowai_test_assert_combined_contains "contract test" "UC-CLI-034" || return

  flowai_test_pass "UC-CLI-034" "flowai run review contract (SKIP_AI) exits 0 after fixture"
}

# UC-CLI-035 / tests/usecases/035-cli-multi-spec-dir-test-mode.md
# Guards: multi-spec-dir resolution does NOT prompt/hang in test/CI mode.
flowai_test_s_cli_035() {
  if flowai_test_skip_if_missing_jq "UC-CLI-035" "multi-spec-dir test mode auto-select"; then return 0; fi
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  flowai_test_invoke_in_dir "$tmp" init
  flowai_test_assert_rc 0 "UC-CLI-035" || return

  # Two spec dirs — both need spec.md so the plan phase can resolve the feature dir
  mkdir -p "$tmp/specs/feature-a"
  mkdir -p "$tmp/specs/feature-b"
  printf 'ok\n' >"$tmp/specs/feature-a/spec.md"
  printf 'ok\n' >"$tmp/specs/feature-b/spec.md"
  mkdir -p "$tmp/.flowai/signals"
  touch "$tmp/.flowai/signals/spec.ready"

  # FLOWAI_TESTING=1 is set by tests/run.sh — the phase must auto-select without prompting
  flowai_test_invoke_in_dir_env "$tmp" FLOWAI_TEST_SKIP_AI=1 "$FLOWAI_BIN" run plan
  flowai_test_assert_rc 0 "UC-CLI-035" || return
  # Must NOT have printed the interactive prompt — test mode must stay silent on multi-dir
  flowai_test_assert_combined_not_contains "please choose one" "UC-CLI-035" || return

  flowai_test_pass "UC-CLI-035" "multiple spec dirs: test mode auto-selects newest without prompting"
}

# UC-CLI-036 — flowai run tasks contract (SKIP_AI)
# Guards: tasks.sh previously had no FLOWAI_TEST_SKIP_AI guard.
flowai_test_s_cli_036() {
  if flowai_test_skip_if_missing_jq "UC-CLI-036" "flowai run tasks contract"; then return 0; fi
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  flowai_test_invoke_in_dir "$tmp" init
  flowai_test_assert_rc 0 "UC-CLI-036" || return

  mkdir -p "$tmp/specs/feat-tasks"
  printf 'ok\n' >"$tmp/specs/feat-tasks/spec.md"
  printf 'ok\n' >"$tmp/specs/feat-tasks/plan.md"
  mkdir -p "$tmp/.flowai/signals"
  touch "$tmp/.flowai/signals/plan.ready"

  flowai_test_invoke_in_dir_env "$tmp" FLOWAI_TEST_SKIP_AI=1 "$FLOWAI_BIN" run tasks
  flowai_test_assert_rc 0 "UC-CLI-036" || return
  flowai_test_assert_combined_contains "contract test" "UC-CLI-036" || return

  flowai_test_pass "UC-CLI-036" "flowai run tasks contract (SKIP_AI) exits 0 after fixture"
}

# UC-CLI-037 — flowai run spec contract (SKIP_AI)
# Guards: spec.sh previously had no FLOWAI_TEST_SKIP_AI guard.
flowai_test_s_cli_037() {
  if flowai_test_skip_if_missing_jq "UC-CLI-037" "flowai run spec contract"; then return 0; fi
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  flowai_test_invoke_in_dir "$tmp" init
  flowai_test_assert_rc 0 "UC-CLI-037" || return

  mkdir -p "$tmp/specs/feat-spec"

  flowai_test_invoke_in_dir_env "$tmp" FLOWAI_TEST_SKIP_AI=1 "$FLOWAI_BIN" run spec
  flowai_test_assert_rc 0 "UC-CLI-037" || return
  flowai_test_assert_combined_contains "contract test" "UC-CLI-037" || return

  flowai_test_pass "UC-CLI-037" "flowai run spec contract (SKIP_AI) exits 0 after fixture"
}

# UC-CLI-038 / tests/usecases/038-cli-mcp-preserves-existing.md
flowai_test_s_cli_038() {
  if flowai_test_skip_if_missing_jq "UC-CLI-038" "mcp list preserves existing mcp.json"; then return 0; fi
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  flowai_test_invoke_in_dir "$tmp" init
  flowai_test_assert_rc 0 "UC-CLI-038" || return

  printf '{"mcpServers":{"mycustom":{"command":"npx","args":["foo"]}}}\n' > "$tmp/.flowai/mcp.json"

  flowai_test_invoke_in_dir "$tmp" mcp list
  flowai_test_assert_rc 0 "UC-CLI-038" || return

  if ! jq -e '.mcpServers | has("mycustom")' "$tmp/.flowai/mcp.json" >/dev/null 2>&1; then
    printf 'FAIL UC-CLI-038: mcp.json was overwritten\n' >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    return 1
  fi

  if jq -e '.mcpServers | has("context7")' "$tmp/.flowai/mcp.json" >/dev/null 2>&1; then
    printf 'FAIL UC-CLI-038: mcp.json was merged when it should only be preserved\n' >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
    return 1
  fi

  flowai_test_pass "UC-CLI-038" "flowai mcp list preserves existing user mcp.json without overwriting/merging"
}

# UC-CLI-041 / tests/usecases/041-cli-logs.md
# Verifies the CLI entrypoint for flowai logs (headless check)
flowai_test_s_cli_041() {
  if flowai_test_skip_if_missing_jq "UC-CLI-041" "flowai logs"; then return 0; fi
  if flowai_test_skip_if_missing_tmux "UC-CLI-041" "flowai logs"; then return 0; fi
  local tmp sess
  tmp="$(mktemp -d)"
  tmp="$(cd "$tmp" && pwd)"
  sess="$(FLOWAI_HOME="$FLOWAI_HOME" bash -c 'source "$FLOWAI_HOME/src/core/session.sh"; flowai_session_name "$1"' _ "$tmp")"
  trap 'tmux kill-session -t "$sess" 2>/dev/null || true; rm -rf "$tmp"' RETURN

  flowai_test_invoke_in_dir "$tmp" init
  flowai_test_assert_rc 0 "UC-CLI-041" || return

  # Should fail when no session exists
  flowai_test_invoke_in_dir "$tmp" logs
  flowai_test_assert_rc 1 "UC-CLI-041" || return
  flowai_test_assert_combined_contains "is not running" "UC-CLI-041" || return

  flowai_test_invoke_in_dir "$tmp" start --headless
  flowai_test_assert_rc 0 "UC-CLI-041" || return

  # Start pane is just outputting the master loop, let's inject a line
  tmux send-keys -t "${sess}:master" "echo 'UC_CLI_041_DETERMINISTIC_LOG'" C-m
  sleep 1

  # Test default logs (should be master)
  flowai_test_invoke_in_dir "$tmp" logs
  flowai_test_assert_rc 0 "UC-CLI-041" || return
  flowai_test_assert_combined_contains "UC_CLI_041_DETERMINISTIC_LOG" "UC-CLI-041" || return

  # Test specific phase
  flowai_test_invoke_in_dir "$tmp" logs master
  flowai_test_assert_rc 0 "UC-CLI-041" || return
  flowai_test_assert_combined_contains "UC_CLI_041_DETERMINISTIC_LOG" "UC-CLI-041" || return

  # Test invalid phase
  flowai_test_invoke_in_dir "$tmp" logs nonexistent
  flowai_test_assert_rc 1 "UC-CLI-041" || return
  flowai_test_assert_combined_contains "not currently running" "UC-CLI-041" || return

  flowai_test_pass "UC-CLI-041" "flowai logs entrypoint correctly fetches TMUX buffers and handles errors"
}
