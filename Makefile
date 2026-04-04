.DEFAULT_GOAL := help
.PHONY: help install lint test verify-usecases verify-ai check

# Colors
YELLOW := \033[33m
CYAN   := \033[36m
BOLD   := \033[1m
RESET  := \033[0m

# FlowAI — Open Source Make Targets

help:
	@printf "$(BOLD)FlowAI Makefile commands:$(RESET)\n\n"
	@printf "  $(CYAN)make install$(RESET)        Install FlowAI globally (/usr/local/bin)\n"
	@printf "  $(CYAN)make audit$(RESET)          Run linters, automated test harness, and AI review\n\n"

install:
	@bash ./install.sh

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
	@if command -v shellcheck >/dev/null 2>&1; then \
		printf "$(CYAN)Running ShellCheck...$(RESET)\n"; \
		shellcheck -x bin/flowai install.sh src/commands/*.sh src/phases/*.sh src/core/*.sh src/bootstrap/*.sh tests/run.sh tests/lib/*.sh tests/lib/verify-bindings.sh tests/suites/*.sh tests/agent/*.sh tests/agent/run-ai-smoke.sh; \
	else \
		printf "\n$(YELLOW)╭──────────────────────────────────────────────────────╮$(RESET)\n"; \
		printf "$(YELLOW)│ [!] WARNING: shellcheck not found in PATH            │$(RESET)\n"; \
		printf "$(YELLOW)│     Skipping linting! Run: brew install shellcheck   │$(RESET)\n"; \
		printf "$(YELLOW)╰──────────────────────────────────────────────────────╯$(RESET)\n\n"; \
	fi

audit: lint verify-ai
