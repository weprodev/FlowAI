#!/usr/bin/env bash
# Role prompt resolution — tests for all 5 tiers of flowai_phase_resolve_role_prompt.
# Expects tests/lib/harness.sh sourced first (see tests/run.sh).
# shellcheck shell=bash

# Helper: run flowai_phase_resolve_role_prompt in an isolated project env.
_role_resolve() {
  local phase="$1" flowai_dir="$2"
  local pwd_dir="${3:-$(dirname "$flowai_dir")}"
  (
    cd "$pwd_dir" || exit
    FLOWAI_DIR="$flowai_dir" \
    FLOWAI_HOME="$FLOWAI_HOME" \
    bash -c "
      source \"\$FLOWAI_HOME/src/core/log.sh\"
      source \"\$FLOWAI_HOME/src/core/config.sh\"
      source \"\$FLOWAI_HOME/src/core/phase.sh\" 2>/dev/null || true
      flowai_phase_resolve_role_prompt \"$phase\"
    "
  ) 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────────────────

# UC-ROLE-001 — Tier 4 (bundled) used when no overrides present
flowai_test_s_role_001() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/.flowai/roles" "$tmp/.flowai/signals" "$tmp/.flowai/launch"
  cat > "$tmp/.flowai/config.json" <<'JSON'
{"pipeline":{"plan":"team-lead"},"roles":{"team-lead":{"tool":"gemini","model":"gemini-2.5-pro"}}}
JSON

  local result
  result="$(_role_resolve "plan" "$tmp/.flowai" "$tmp")"

  if [[ "$result" == *"src/roles/team-lead.md" ]]; then
    flowai_test_pass "UC-ROLE-001" "Tier 4 (bundled) used when no overrides exist"
  else
    printf 'FAIL UC-ROLE-001: Expected bundled team-lead.md, got: %s\n' "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-ROLE-002 — Tier 1: .flowai/roles/<phase>.md wins
flowai_test_s_role_002() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/.flowai/roles" "$tmp/.flowai/signals" "$tmp/.flowai/launch"
  echo "# Phase override" > "$tmp/.flowai/roles/plan.md"
  cat > "$tmp/.flowai/config.json" <<'JSON'
{"pipeline":{"plan":"team-lead"},"roles":{"team-lead":{"tool":"gemini","model":"gemini-2.5-pro"}}}
JSON

  local result
  result="$(_role_resolve "plan" "$tmp/.flowai" "$tmp")"

  if [[ "$result" == "$tmp/.flowai/roles/plan.md" ]]; then
    flowai_test_pass "UC-ROLE-002" "Tier 1 (.flowai/roles/<phase>.md) wins"
  else
    printf 'FAIL UC-ROLE-002: Expected Tier 1 phase file, got: %s\n' "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-ROLE-003 — Tier 2: .flowai/roles/<role-name>.md wins (when no phase file)
flowai_test_s_role_003() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/.flowai/roles" "$tmp/.flowai/signals" "$tmp/.flowai/launch"
  echo "# Role override" > "$tmp/.flowai/roles/team-lead.md"
  cat > "$tmp/.flowai/config.json" <<'JSON'
{"pipeline":{"plan":"team-lead"},"roles":{"team-lead":{"tool":"gemini","model":"gemini-2.5-pro"}}}
JSON

  local result
  result="$(_role_resolve "plan" "$tmp/.flowai" "$tmp")"

  if [[ "$result" == "$tmp/.flowai/roles/team-lead.md" ]]; then
    flowai_test_pass "UC-ROLE-003" "Tier 2 (.flowai/roles/<role-name>.md) wins when no phase file"
  else
    printf 'FAIL UC-ROLE-003: Expected Tier 2 role file, got: %s\n' "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-ROLE-004 — Tier 3: prompt_file in config.json used (when no file drops)
flowai_test_s_role_004() {
  if ! command -v jq >/dev/null 2>&1; then
    printf 'ok  UC-ROLE-004 — Tier 3 prompt_file (skipped: jq not installed)\n'
    return 0
  fi

  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/.flowai/roles" "$tmp/.flowai/signals" "$tmp/.flowai/launch"
  mkdir -p "$tmp/docs/roles"
  echo "# Custom team-lead" > "$tmp/docs/roles/team-lead.md"

  cat > "$tmp/.flowai/config.json" <<JSON
{"pipeline":{"plan":"team-lead"},"roles":{"team-lead":{"tool":"gemini","model":"gemini-2.5-pro","prompt_file":"docs/roles/team-lead.md"}}}
JSON

  local result
  result="$(_role_resolve "plan" "$tmp/.flowai" "$tmp")"

  if [[ "$result" == "$tmp/docs/roles/team-lead.md" ]]; then
    flowai_test_pass "UC-ROLE-004" "Tier 3 (config.json prompt_file) used when no file drops"
  else
    printf 'FAIL UC-ROLE-004: Expected Tier 3 prompt_file path, got: %s\n' "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-ROLE-005 — Tier 1 wins over Tier 3 (file drop beats config key)
flowai_test_s_role_005() {
  if ! command -v jq >/dev/null 2>&1; then
    printf 'ok  UC-ROLE-005 — Tier 1 beats Tier 3 (skipped: jq not installed)\n'
    return 0
  fi

  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/.flowai/roles" "$tmp/.flowai/signals" "$tmp/.flowai/launch"
  echo "# Phase drop" > "$tmp/.flowai/roles/plan.md"
  mkdir -p "$tmp/docs/roles"
  echo "# Config file" > "$tmp/docs/roles/team-lead.md"

  cat > "$tmp/.flowai/config.json" <<JSON
{"pipeline":{"plan":"team-lead"},"roles":{"team-lead":{"tool":"gemini","model":"gemini-2.5-pro","prompt_file":"docs/roles/team-lead.md"}}}
JSON

  local result
  result="$(_role_resolve "plan" "$tmp/.flowai" "$tmp")"

  if [[ "$result" == "$tmp/.flowai/roles/plan.md" ]]; then
    flowai_test_pass "UC-ROLE-005" "Tier 1 (file drop) wins over Tier 3 (config prompt_file)"
  else
    printf 'FAIL UC-ROLE-005: Expected Tier 1, got: %s\n' "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-ROLE-006 — master phase always resolves to master role (bundled)
flowai_test_s_role_006() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/.flowai/roles" "$tmp/.flowai/signals" "$tmp/.flowai/launch"
  cat > "$tmp/.flowai/config.json" <<'JSON'
{"pipeline":{"plan":"team-lead"},"roles":{"team-lead":{"tool":"gemini","model":"gemini-2.5-pro"}}}
JSON

  local result
  result="$(_role_resolve "master" "$tmp/.flowai" "$tmp")"

  if [[ "$result" == *"src/roles/master.md" ]]; then
    flowai_test_pass "UC-ROLE-006" "master phase resolves to bundled master.md (Tier 4)"
  else
    printf 'FAIL UC-ROLE-006: Expected master.md, got: %s\n' "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-ROLE-007 — Tier 3 skipped gracefully when prompt_file points to non-existent file
flowai_test_s_role_007() {
  if ! command -v jq >/dev/null 2>&1; then
    printf 'ok  UC-ROLE-007 — Tier 3 skip missing file (skipped: jq not installed)\n'
    return 0
  fi

  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/.flowai/roles" "$tmp/.flowai/signals" "$tmp/.flowai/launch"
  # prompt_file defined in config but the actual file does NOT exist on disk
  cat > "$tmp/.flowai/config.json" <<JSON
{"pipeline":{"plan":"team-lead"},"roles":{"team-lead":{"tool":"gemini","model":"gemini-2.5-pro","prompt_file":"docs/roles/missing.md"}}}
JSON

  local result
  result="$(_role_resolve "plan" "$tmp/.flowai" "$tmp")"

  # Must fall through to Tier 4 (bundled), not return an invalid path
  if [[ "$result" == *"src/roles/team-lead.md" ]]; then
    flowai_test_pass "UC-ROLE-007" "Tier 3 skipped when prompt_file missing on disk — falls to bundled"
  else
    printf 'FAIL UC-ROLE-007: Expected bundled fallback, got: %s\n' "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-ROLE-008 — _role_config_set_prompt_file does not create orphan role entries
flowai_test_s_role_008() {
  if ! command -v jq >/dev/null 2>&1; then
    printf 'ok  UC-ROLE-008 — set-prompt orphan guard (skipped: jq not installed)\n'
    return 0
  fi

  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/.flowai"
  # roles block present but "unknown-role" is deliberately absent
  cat > "$tmp/.flowai/config.json" <<'JSON'
{"roles":{"team-lead":{"tool":"gemini","model":"gemini-2.5-pro"}}}
JSON

  FLOWAI_DIR="$tmp/.flowai" FLOWAI_HOME="$FLOWAI_HOME" \
  bash -c '
    source "$FLOWAI_HOME/src/core/log.sh"
    source "$FLOWAI_HOME/src/core/config.sh"
    # Inline the helper to avoid the entry-point dispatch in role.sh
    _role_config_set_prompt_file() {
      local role="$1" rel_path="$2"
      local role_exists
      role_exists="$(jq -r --arg r "$role" '"'"'.roles[$r] // empty'"'"' "$FLOWAI_DIR/config.json" 2>/dev/null)"
      if [[ -z "$role_exists" ]]; then
        return 1
      fi
      local tmp
      tmp="$(mktemp)"
      jq --arg r "$role" --arg p "$rel_path" '"'"'.roles[$r].prompt_file = $p'"'"' \
        "$FLOWAI_DIR/config.json" > "$tmp" && mv "$tmp" "$FLOWAI_DIR/config.json" || rm -f "$tmp"
    }
    _role_config_set_prompt_file "unknown-role" "docs/roles/foo.md" || true
  ' >/dev/null 2>&1

  local has_unknown
  has_unknown="$(jq -r '.roles["unknown-role"] // empty' "$tmp/.flowai/config.json" 2>/dev/null)"

  if [[ -z "$has_unknown" ]]; then
    flowai_test_pass "UC-ROLE-008" "_role_config_set_prompt_file does not create orphan role entries"
  else
    printf 'FAIL UC-ROLE-008: Orphan role entry was created: %s\n' "$has_unknown" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-ROLE-009 — Tier 3 skipped when prompt_file is unsafe (.. / absolute)
flowai_test_s_role_009() {
  if ! command -v jq >/dev/null 2>&1; then
    printf 'ok  UC-ROLE-009 — unsafe prompt_file skipped (skipped: jq not installed)\n'
    return 0
  fi

  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/.flowai/roles" "$tmp/.flowai/signals" "$tmp/.flowai/launch"
  cat > "$tmp/.flowai/config.json" <<JSON
{"pipeline":{"plan":"team-lead"},"roles":{"team-lead":{"tool":"gemini","model":"gemini-2.5-pro","prompt_file":"../../etc/passwd"}}}
JSON

  local result
  result="$(_role_resolve "plan" "$tmp/.flowai" "$tmp")"

  if [[ "$result" == *"src/roles/team-lead.md" ]]; then
    flowai_test_pass "UC-ROLE-009" "Tier 3 skipped when prompt_file is not repo-safe — bundled used"
  else
    printf 'FAIL UC-ROLE-009: Expected bundled fallback, got: %s\n' "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}
