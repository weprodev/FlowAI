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

# Only binding check (verbose); does not run the harness
verify-usecases:
	@bash tests/agent/verify-usecases.sh

# Deterministic tests + optional LLM review (Gemini or Claude) — see tests/agent/run-ai-smoke.sh
verify-ai:
	@bash tests/agent/run-ai-smoke.sh

lint:
	@bash scripts/lint.sh

# Sequential gate: lint, then tests/run.sh, then optional LLM smoke (verify-ai).
audit:
	@$(MAKE) lint
	@$(MAKE) test
	@$(MAKE) verify-ai

# Fetch/refresh bundled skills from their upstream sources.
# Run this when upstream skills are updated; commit the result.
build-skills:
	@bash scripts/build-skills.sh

# Cut a new release interactively (bumps version, commits, tags, and pushes)
release:
	@bash scripts/release.sh
