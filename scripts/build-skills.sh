#!/usr/bin/env bash
# Fetch/refresh bundled skills from their upstream sources.
# Run this when upstream skills are updated; commit the result.

set -euo pipefail

CYAN=$'\033[36m'
RESET=$'\033[0m'

printf "%bFetching bundled skills from obra/superpowers...%b\n" "$CYAN" "$RESET"

SKILLS=(
  systematic-debugging
  test-driven-development
  requesting-code-review
  executing-plans
  verification-before-completion
  writing-plans
  subagent-driven-development
  finishing-a-development-branch
)

failures=0

for skill in "${SKILLS[@]}"; do
  mkdir -p "src/skills/$skill"
  if curl -fsSL "https://raw.githubusercontent.com/obra/superpowers/main/skills/$skill/SKILL.md" -o "src/skills/$skill/SKILL.md"; then
    printf "  ✓ %s\n" "$skill"
  else
    printf "  ✗ %s (failed)\n" "$skill"
    failures=$((failures + 1))
  fi
done

printf "%bDone.%b\n" "$CYAN" "$RESET"

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi
