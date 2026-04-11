.DEFAULT_GOAL := help
SHELL := /bin/bash
.PHONY: help install link uninstall lint test verify-usecases verify-ai check build-skills

# Colors
YELLOW := \033[33m
CYAN   := \033[36m
BOLD   := \033[1m
RESET  := \033[0m

# FlowAI — Open Source Make Targets

help:
	@printf "$(BOLD)FlowAI Makefile commands:$(RESET)\n\n"
	@printf "  $(CYAN)make link$(RESET)           Developer install — symlink to this workspace (edits are live)\n"
	@printf "  $(CYAN)make install$(RESET)        Production install — copy to /usr/local/flowai\n"
	@printf "  $(CYAN)make uninstall$(RESET)      Remove FlowAI from system\n"
	@printf "  $(CYAN)make test$(RESET)           Run the full test suite\n"
	@printf "  $(CYAN)make audit$(RESET)          Lint → tests → optional AI review\n"
	@printf "  $(CYAN)make build-skills$(RESET)   Fetch/refresh bundled skills from skills.sh sources\n"
	@printf "  $(CYAN)make release$(RESET)        Cut a new release interactively (bump, commit, tag, push)\n\n"

link:
	@bash ./install.sh --link

install:
	@bash ./install.sh

uninstall:
	@bash ./install.sh --uninstall

# Application use cases: specs in tests/usecases/ — see tests/usecases/README.md
test:
	@bash tests/run.sh

# Convenience alias (CI / habit): same as `make test` here.
check: test

# Only binding check (verbose); does not run the harness
verify-usecases:
	@bash tests/agent/verify-usecases.sh

# Deterministic tests + optional LLM review (Gemini or Claude) — see tests/agent/run-ai-smoke.sh
verify-ai:
	@bash tests/agent/run-ai-smoke.sh

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		printf "$(CYAN)Running ShellCheck...$(RESET)\n"; \
		set -e; \
		shopt -s nullglob; \
		for f in \
			bin/flowai \
			install.sh \
			src/commands/*.sh \
			src/phases/*.sh \
			src/core/*.sh \
			src/bootstrap/*.sh \
			tests/run.sh \
			tests/lib/*.sh \
			tests/suites/*.sh \
			tests/agent/*.sh; \
		do \
			printf "  $(CYAN)shellcheck$(RESET) %s\n" "$$f"; \
			shellcheck -x "$$f"; \
		done; \
	else \
		printf "\n$(YELLOW)╭──────────────────────────────────────────────────────╮$(RESET)\n"; \
		printf "$(YELLOW)│ [!] WARNING: shellcheck not found in PATH            │$(RESET)\n"; \
		printf "$(YELLOW)│     Skipping linting! Run: brew install shellcheck   │$(RESET)\n"; \
		printf "$(YELLOW)╰──────────────────────────────────────────────────────╯$(RESET)\n\n"; \
	fi

# Sequential gate: lint, then tests/run.sh, then optional LLM smoke (verify-ai).
audit:
	@$(MAKE) lint
	@$(MAKE) test
	@$(MAKE) verify-ai

# Fetch/refresh bundled skills from their upstream sources.
# Run this when upstream skills are updated; commit the result.
build-skills:
	@printf "$(CYAN)Fetching bundled skills from obra/superpowers...$(RESET)\n"
	@for skill in systematic-debugging test-driven-development requesting-code-review \
	             executing-plans verification-before-completion writing-plans \
	             subagent-driven-development finishing-a-development-branch; do \
	  mkdir -p "src/skills/$$skill"; \
	  curl -fsSL "https://raw.githubusercontent.com/obra/superpowers/main/skills/$$skill/SKILL.md" \
	    -o "src/skills/$$skill/SKILL.md" && printf "  ✓ $$skill\n" || printf "  ✗ $$skill (failed)\n"; \
	done
	@printf "$(CYAN)Done.$(RESET)\n"

# Cut a new release interactively (bumps version, commits, tags, and pushes)
release:
	@bash scripts/release.sh
