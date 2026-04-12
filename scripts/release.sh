#!/usr/bin/env bash
# Release automation script

set -euo pipefail

BOLD=$'\033[1m'
GREEN=$'\033[32m'
CYAN=$'\033[36m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
RESET=$'\033[0m'

# Check working tree
if [[ -n "$(git status --porcelain)" ]]; then
  printf "%bError: Working directory is not clean.%b\n" "$RED" "$RESET"
  printf "Please commit or stash your changes before cutting a release.\n"
  exit 1
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$BRANCH" != "main" ]]; then
  printf "%bChecking out main branch...%b\n" "$CYAN" "$RESET"
  git checkout main
fi

printf "%bPulling latest changes from origin/main...%b\n" "$CYAN" "$RESET"
git pull origin main

if [[ ! -f "VERSION" ]]; then
  printf "%bError: VERSION file not found.%b\n" "$RED" "$RESET"
  exit 1
fi

CURRENT_VERSION="$(cat VERSION | tr -d '[:space:]')"
printf "Current VERSION: %b%s%b\n" "$BOLD" "$CURRENT_VERSION" "$RESET"

# Check if tag exists
if git rev-parse "v${CURRENT_VERSION}" >/dev/null 2>&1; then
  printf "\n%bGit tag v%s already exists.%b\n" "$YELLOW" "$CURRENT_VERSION" "$RESET"
  printf "Please bump the version to cut a new release.\n\n"
  
  # Parse current version
  IFS='.' read -r -a parts <<< "$CURRENT_VERSION"
  v_major="${parts[0]:-0}"
  v_minor="${parts[1]:-0}"
  v_patch="${parts[2]:-0}"
  
  opt_major="$((v_major + 1)).0.0"
  opt_minor="${v_major}.$((v_minor + 1)).0"
  opt_patch="${v_major}.${v_minor}.$((v_patch + 1))"

  echo "Select bump type:"
  echo "  1) Patch (${opt_patch})"
  echo "  2) Minor (${opt_minor})"
  echo "  3) Major (${opt_major})"
  echo "  4) Cancel"
  
  while true; do
    printf "Selection (1-4): "
    read -r choice
    case "$choice" in
      1) NEW_VERSION="$opt_patch"; break ;;
      2) NEW_VERSION="$opt_minor"; break ;;
      3) NEW_VERSION="$opt_major"; break ;;
      4) printf "Release aborted.\n"; exit 0 ;;
      *) printf "Invalid selection.\n" ;;
    esac
  done

  printf "\nBump version to %b%s%b? (y/n) " "$BOLD" "$NEW_VERSION" "$RESET"
  read -r confirm </dev/tty
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    printf "Release aborted.\n"
    exit 0
  fi
else
  printf "\n%bCurrent VERSION (v%s) is not tagged yet.%b\n" "$GREEN" "$CURRENT_VERSION" "$RESET"
  printf "We will target this version for the release.\n\n"
  
  printf "Proceed with releasing %bv%s%b? (y/n) " "$BOLD" "$CURRENT_VERSION" "$RESET"
  read -r confirm </dev/tty
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    printf "Release aborted.\n"
    exit 0
  fi
  NEW_VERSION="$CURRENT_VERSION"
fi

# Generate changelog for this release
PREV_TAG="$(git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
CHANGELOG_CONTENT="Release v${NEW_VERSION}\n\n"

if [[ -n "$PREV_TAG" ]]; then
  # Grab commits since previous tag
  CHANGELOG_CONTENT+=$(git log "${PREV_TAG}..HEAD" --oneline --no-merges --pretty=format:"- %s" || echo "- Released v${NEW_VERSION}")
else
  CHANGELOG_CONTENT+="- Initial Release"
fi

printf "%s\n" "$NEW_VERSION" > VERSION
git add VERSION

# Commit if there's anything modified (VERSION)
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "chore(release): bump version to v${NEW_VERSION}"
fi

CURRENT_VERSION="$NEW_VERSION"

printf "\n%bPushing commits to main...%b\n" "$CYAN" "$RESET"
git push origin main

printf "\n%bCreating and pushing tag v%s...%b\n" "$CYAN" "$CURRENT_VERSION" "$RESET"
git tag -a "v${CURRENT_VERSION}" -m "$(printf "%b" "$CHANGELOG_CONTENT")"
git push origin "v${CURRENT_VERSION}"

printf "\n%b✅ Successfully released v%s!%b\n" "$GREEN" "$CURRENT_VERSION" "$RESET"
printf "GitHub Actions will now build and publish the release.\n"
