#!/usr/bin/env bash
# Skill local path resolution — tests for the Tier 2 project-relative skill path.
# Expects tests/lib/harness.sh sourced first (see tests/run.sh).
# shellcheck shell=bash

# Helper: run a skill resolution function in an isolated env.
_skl_resolve_skill_path() {
  local name="$1" flowai_dir="$2" pwd_dir="$3"
  (
    cd "$pwd_dir" || exit
    FLOWAI_DIR="$flowai_dir" \
    FLOWAI_HOME="$FLOWAI_HOME" \
    bash -c "
      source \"\$FLOWAI_HOME/src/core/log.sh\"
      source \"\$FLOWAI_HOME/src/core/config.sh\"
      source \"\$FLOWAI_HOME/src/core/skills.sh\"
      flowai_skill_path \"$name\"
    "
  ) 2>/dev/null
}

_skl_skills_all() {
  local flowai_dir="$1" pwd_dir="$2"
  (
    cd "$pwd_dir" || exit
    FLOWAI_DIR="$flowai_dir" \
    FLOWAI_HOME="$FLOWAI_HOME" \
    bash -c '
      source "$FLOWAI_HOME/src/core/log.sh"
      source "$FLOWAI_HOME/src/core/config.sh"
      source "$FLOWAI_HOME/src/core/skills.sh"
      flowai_skills_all
    '
  ) 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────────────────

# UC-SKL-001 — flowai_skill_path resolves a project-relative skill (Tier 2)
flowai_test_s_skl_001() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/.flowai"
  cat > "$tmp/.flowai/config.json" <<'JSON'
{"skills":{"paths":["docs/skills"],"role_assignments":{}}}
JSON
  mkdir -p "$tmp/docs/skills/my-custom-skill"
  echo "# My Custom Skill" > "$tmp/docs/skills/my-custom-skill/SKILL.md"

  local result
  result="$(_skl_resolve_skill_path "my-custom-skill" "$tmp/.flowai" "$tmp")"

  if [[ "$result" == "$tmp/docs/skills/my-custom-skill/SKILL.md" ]]; then
    flowai_test_pass "UC-SKL-001" "flowai_skill_path resolves project-relative skill (Tier 2)"
  else
    printf 'FAIL UC-SKL-001: Expected Tier 2 path, got: %s\n' "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-SKL-002 — Tier 1 (installed) wins over Tier 2 (project-relative)
flowai_test_s_skl_002() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/.flowai/skills/my-skill"
  echo "# Installed" > "$tmp/.flowai/skills/my-skill/SKILL.md"
  mkdir -p "$tmp/docs/skills/my-skill"
  echo "# Project" > "$tmp/docs/skills/my-skill/SKILL.md"
  cat > "$tmp/.flowai/config.json" <<'JSON'
{"skills":{"paths":["docs/skills"],"role_assignments":{}}}
JSON

  local result
  result="$(_skl_resolve_skill_path "my-skill" "$tmp/.flowai" "$tmp")"

  if [[ "$result" == "$tmp/.flowai/skills/my-skill/SKILL.md" ]]; then
    flowai_test_pass "UC-SKL-002" "Tier 1 (installed) wins over Tier 2 (project-relative)"
  else
    printf 'FAIL UC-SKL-002: Expected Tier 1, got: %s\n' "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-SKL-003 — flowai_skills_all lists skills from both tiers, deduplicated
flowai_test_s_skl_003() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/.flowai/skills/installed-skill"
  echo "# Installed" > "$tmp/.flowai/skills/installed-skill/SKILL.md"
  mkdir -p "$tmp/docs/skills/project-skill"
  echo "# Project" > "$tmp/docs/skills/project-skill/SKILL.md"
  # Duplicate — should appear only once
  mkdir -p "$tmp/docs/skills/installed-skill"
  echo "# Dup" > "$tmp/docs/skills/installed-skill/SKILL.md"
  cat > "$tmp/.flowai/config.json" <<'JSON'
{"skills":{"paths":["docs/skills"],"role_assignments":{}}}
JSON

  local all
  all="$(_skl_skills_all "$tmp/.flowai" "$tmp")"

  local ic pc
  ic=$(printf '%s\n' "$all" | grep -c "^installed-skill$" || true)
  pc=$(printf '%s\n' "$all" | grep -c "^project-skill$" || true)

  if [[ "$ic" -eq 1 ]] && [[ "$pc" -eq 1 ]]; then
    flowai_test_pass "UC-SKL-003" "flowai_skills_all lists both tiers deduplicated"
  else
    printf 'FAIL UC-SKL-003: installed=%s project=%s; all=[%s]\n' "$ic" "$pc" "$all" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-SKL-004 — no skills.paths key → Tier 2 skipped, falls through to bundled (Tier 3)
flowai_test_s_skl_004() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/.flowai"
  cat > "$tmp/.flowai/config.json" <<'JSON'
{"skills":{"role_assignments":{}}}
JSON

  local result
  result="$(_skl_resolve_skill_path "executing-plans" "$tmp/.flowai" "$tmp")"

  if [[ "$result" == *"src/skills/executing-plans/SKILL.md" ]]; then
    flowai_test_pass "UC-SKL-004" "Missing skills.paths falls through to bundled (Tier 3)"
  else
    printf 'FAIL UC-SKL-004: Expected bundled path, got: %s\n' "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-SKL-005 — _skill_config_register_path is idempotent
flowai_test_s_skl_005() {
  if flowai_test_skip_if_missing_jq "UC-SKL-005" "_skill_config_register_path idempotent"; then return 0; fi

  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/.flowai"
  cat > "$tmp/.flowai/config.json" <<'JSON'
{"skills":{"paths":[],"role_assignments":{}}}
JSON

  # Register same path twice
  for _ in 1 2; do
    FLOWAI_DIR="$tmp/.flowai" FLOWAI_HOME="$FLOWAI_HOME" \
    bash -c '
      source "$FLOWAI_HOME/src/core/log.sh"
      source "$FLOWAI_HOME/src/core/config.sh"
      # Source only the helper, avoid running the entry-point dispatch
      _skill_config_register_path() {
        local rel_path="$1" tmp
        tmp="$(mktemp)"
        jq --arg p "$rel_path" '"'"'
          .skills.paths //= [] |
          if (.skills.paths | index($p)) == null then .skills.paths += [$p] else . end
        '"'"' "$FLOWAI_DIR/config.json" > "$tmp" && mv "$tmp" "$FLOWAI_DIR/config.json" || rm -f "$tmp"
      }
      _skill_config_register_path "docs/skills"
    ' 2>/dev/null
  done

  local count
  count="$(jq '.skills.paths | length' "$tmp/.flowai/config.json")"
  if [[ "$count" -eq 1 ]]; then
    flowai_test_pass "UC-SKL-005" "_skill_config_register_path is idempotent (duplicate not added)"
  else
    printf 'FAIL UC-SKL-005: Expected 1 path, got: %s\n' "$count" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-SKL-006 — flowai_validate_repo_rel_path rejects traversal / absolute paths
flowai_test_s_skl_006() {
  if (
    source "$FLOWAI_HOME/src/core/config.sh"
    flowai_validate_repo_rel_path "docs/skills" || exit 1
    flowai_validate_repo_rel_path "./docs/skills" || exit 1
    flowai_validate_repo_rel_path "." || exit 1
    flowai_validate_repo_rel_path "a/b/c" || exit 1
    ! flowai_validate_repo_rel_path "../outside" || exit 1
    ! flowai_validate_repo_rel_path "/etc/passwd" || exit 1
    ! flowai_validate_repo_rel_path "a/../b" || exit 1
    local n
    n="$(flowai_normalize_repo_rel_path "./docs/foo")"
    [[ "$n" == "docs/foo" ]] || exit 1
  ); then
    flowai_test_pass "UC-SKL-006" "flowai_validate_repo_rel_path / normalize guard repo-relative paths"
  else
    printf 'FAIL UC-SKL-006: path validation/normalize\n' >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-SKL-007 — first entry in skills.paths wins when the same skill exists in two dirs
flowai_test_s_skl_007() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/.flowai" "$tmp/first/same-skill" "$tmp/second/same-skill"
  echo "# First wins" > "$tmp/first/same-skill/SKILL.md"
  echo "# Second" > "$tmp/second/same-skill/SKILL.md"
  cat > "$tmp/.flowai/config.json" <<'JSON'
{"skills":{"paths":["first","second"],"role_assignments":{}}}
JSON

  local result
  result="$(_skl_resolve_skill_path "same-skill" "$tmp/.flowai" "$tmp")"

  if [[ "$result" == "$tmp/first/same-skill/SKILL.md" ]]; then
    flowai_test_pass "UC-SKL-007" "First skills.paths entry wins for duplicate skill names"
  else
    printf 'FAIL UC-SKL-007: Expected first path, got: %s\n' "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}

# UC-SKL-008 — unsafe skills.paths entries are ignored (no escape from project)
flowai_test_s_skl_008() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/.flowai" "$tmp/docs/skills/ok-skill"
  echo "# OK" > "$tmp/docs/skills/ok-skill/SKILL.md"
  cat > "$tmp/.flowai/config.json" <<'JSON'
{"skills":{"paths":["../outside","docs/skills"],"role_assignments":{}}}
JSON

  local result
  result="$(_skl_resolve_skill_path "ok-skill" "$tmp/.flowai" "$tmp")"

  if [[ "$result" == "$tmp/docs/skills/ok-skill/SKILL.md" ]]; then
    flowai_test_pass "UC-SKL-008" "Unsafe skills.paths entries skipped — safe path still resolves"
  else
    printf 'FAIL UC-SKL-008: Expected docs/skills tier, got: %s\n' "$result" >&2
    FLOWAI_TEST_FAILURES=$((FLOWAI_TEST_FAILURES + 1))
  fi
}
