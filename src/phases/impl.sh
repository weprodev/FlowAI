#!/usr/bin/env bash
# FlowAI — shim phase for legacy `impl` alias
# shellcheck shell=bash

set -euo pipefail

# Allow direct invocation of impl even though the canonical script is implement.sh
FLOWAI_HOME="${FLOWAI_HOME:-$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)}"

exec "$FLOWAI_HOME/src/phases/implement.sh" "$@"
#!/usr/bin/env bash
# FlowAI — compatibility shim for the implement phase
# shellcheck shell=bash

# The canonical phase script is implement.sh. This wrapper preserves the
# historic "impl" phase name used across signals, events, and tests while
# ensuring `flowai run impl` resolves to the correct implementation.
exec "$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/implement.sh" "$@"
