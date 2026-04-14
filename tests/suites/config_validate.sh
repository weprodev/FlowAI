#!/usr/bin/env bash
# FlowAI test suite — config validation against models-catalog.json
# Tests for flowai validate (alias: flowai config validate).
# shellcheck shell=bash

source "$FLOWAI_HOME/src/core/log.sh"

# ─── CFGV-001: Valid config passes validation ────────────────────────────────
flowai_test_s_cfgv_001() {
  if flowai_test_skip_if_missing_jq "CFGV-001" "valid config passes validation"; then return 0; fi
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"

  cat > "$scratch/.flowai/config.json" <<'JSON'
{
  "master": {
    "tool": "gemini",
    "model": "gemini-2.5-pro"
  },
  "pipeline": ["plan", "backend"],
  "roles": {
    "team-lead": {
      "tool": "gemini",
      "model": "gemini-2.5-pro"
    },
    "backend-engineer": {
      "tool": "claude",
      "model": "sonnet"
    }
  }
}
JSON

  flowai_test_invoke_in_dir "$scratch" validate
  flowai_test_assert_rc 0 "CFGV-001" || { rm -rf "$scratch"; return; }
  flowai_test_assert_combined_contains "matches models-catalog" "CFGV-001" || { rm -rf "$scratch"; return; }

  flowai_test_pass "CFGV-001" "valid config with master and roles passes flowai validate"
  rm -rf "$scratch"
}

# ─── CFGV-002: Invalid model for valid tool fails validation ─────────────────
flowai_test_s_cfgv_002() {
  if flowai_test_skip_if_missing_jq "CFGV-002" "invalid model rejected"; then return 0; fi
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"

  cat > "$scratch/.flowai/config.json" <<'JSON'
{
  "master": {
    "tool": "gemini",
    "model": "nonexistent-model-xyz"
  }
}
JSON

  flowai_test_invoke_in_dir "$scratch" validate
  flowai_test_assert_rc 1 "CFGV-002" || { rm -rf "$scratch"; return; }
  flowai_test_assert_combined_contains "Invalid model" "CFGV-002" || { rm -rf "$scratch"; return; }

  flowai_test_pass "CFGV-002" "flowai validate exits 1 when master.model is not in catalog"
  rm -rf "$scratch"
}

# ─── CFGV-003: Missing config.json fails gracefully ─────────────────────────
flowai_test_s_cfgv_003() {
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"
  # Deliberately do NOT create config.json

  flowai_test_invoke_in_dir "$scratch" validate
  flowai_test_assert_rc 1 "CFGV-003" || { rm -rf "$scratch"; return; }
  flowai_test_assert_combined_contains "not found" "CFGV-003" || { rm -rf "$scratch"; return; }

  flowai_test_pass "CFGV-003" "flowai validate exits 1 with error when config.json is missing"
  rm -rf "$scratch"
}

# ─── CFGV-004: Empty config.json passes (defaults apply) ────────────────────
flowai_test_s_cfgv_004() {
  if flowai_test_skip_if_missing_jq "CFGV-004" "empty config uses defaults"; then return 0; fi
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"

  printf '{}' > "$scratch/.flowai/config.json"

  flowai_test_invoke_in_dir "$scratch" validate
  flowai_test_assert_rc 0 "CFGV-004" || { rm -rf "$scratch"; return; }
  flowai_test_assert_combined_contains "matches models-catalog" "CFGV-004" || { rm -rf "$scratch"; return; }

  flowai_test_pass "CFGV-004" "empty {} config passes validation (all fields default)"
  rm -rf "$scratch"
}

# ─── CFGV-005: Config with wrong tool for model produces hint ────────────────
flowai_test_s_cfgv_005() {
  if flowai_test_skip_if_missing_jq "CFGV-005" "wrong tool for model hints correct tool"; then return 0; fi
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"

  cat > "$scratch/.flowai/config.json" <<'JSON'
{
  "roles": {
    "backend-engineer": {
      "tool": "gemini",
      "model": "sonnet"
    }
  }
}
JSON

  flowai_test_invoke_in_dir "$scratch" validate
  flowai_test_assert_rc 1 "CFGV-005" || { rm -rf "$scratch"; return; }
  flowai_test_assert_combined_contains "Hint" "CFGV-005" || { rm -rf "$scratch"; return; }
  flowai_test_assert_combined_contains "claude" "CFGV-005" || { rm -rf "$scratch"; return; }

  flowai_test_pass "CFGV-005" "flowai validate hints that 'sonnet' belongs to 'claude' not 'gemini'"
  rm -rf "$scratch"
}

# ─── CFGV-006: Role with no tool falls back to master tool ──────────────────
flowai_test_s_cfgv_006() {
  if flowai_test_skip_if_missing_jq "CFGV-006" "role without tool falls back to master"; then return 0; fi
  local scratch
  scratch="$(mktemp -d)"
  mkdir -p "$scratch/.flowai"

  cat > "$scratch/.flowai/config.json" <<'JSON'
{
  "master": {
    "tool": "gemini",
    "model": "gemini-2.5-pro"
  },
  "pipeline": ["plan"],
  "roles": {
    "team-lead": {}
  }
}
JSON

  flowai_test_invoke_in_dir "$scratch" validate
  flowai_test_assert_rc 0 "CFGV-006" || { rm -rf "$scratch"; return; }
  flowai_test_assert_combined_contains "matches models-catalog" "CFGV-006" || { rm -rf "$scratch"; return; }

  flowai_test_pass "CFGV-006" "role with no tool/model fields passes validation (falls back to master)"
  rm -rf "$scratch"
}
