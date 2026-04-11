#!/usr/bin/env bash
# FlowAI — Canonical pipeline phase list (single source of truth)
#
# All pipeline phases in execution order. Consumers should source this file
# and reference FLOWAI_PIPELINE_PHASES instead of hardcoding phase names.
#
# master is excluded — it orchestrates the pipeline, it does not participate
# as a phase. Add it explicitly where needed (e.g. CLI menus).
#
# To add a new phase:
#   1. Add the name here (in the correct order)
#   2. Create src/phases/<name>.sh
#   3. That's it — start.sh, eventlog.sh, and bin/flowai all read from here
#
# shellcheck shell=bash

# Include guard — phases.sh may be sourced transitively from multiple files.
if [[ -z "${_FLOWAI_PHASES_LOADED:-}" ]]; then
  # shellcheck disable=SC2034
  readonly _FLOWAI_PHASES_LOADED=1
  # shellcheck disable=SC2034
  readonly FLOWAI_PIPELINE_PHASES=(spec plan tasks impl review)
fi
