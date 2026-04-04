.PHONY: install lint test verify-usecases verify verify-ai check

# FlowAI — Open Source Make Targets

install:
	@bash ./install.sh

# Application use cases: specs in tests/usecases/ — see tests/usecases/README.md
# `verify` = bindings (silent if OK) + harness — single entry, no duplicate spam
test:
	@bash tests/run.sh

verify: test

# Only binding check (verbose); does not run the harness
verify-usecases:
	@bash tests/agent/verify-usecases.sh

# Deterministic tests + optional LLM review (Gemini or Claude) — see tests/agent/run-ai-smoke.sh
verify-ai:
	@bash tests/agent/run-ai-smoke.sh

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		echo "Running ShellCheck..."; \
		shellcheck bin/flowai install.sh src/commands/*.sh src/phases/*.sh src/core/*.sh src/bootstrap/*.sh tests/run.sh tests/lib/*.sh tests/lib/verify-bindings.sh tests/cases/*.sh tests/agent/*.sh tests/agent/run-ai-smoke.sh; \
	else \
		echo "shellcheck not found. Skipping linting (brew install shellcheck)."; \
	fi

check: lint verify
