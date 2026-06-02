#!/bin/bash
# Start a devcontainer and run Claude Code with no permission prompts.
# Usage: .devcontainer/claude.sh [args...]
set -e

# shellcheck disable=SC1091
source "$(dirname "$0")/start.sh"

devcontainer exec --workspace-folder "$WORKSPACE" \
  claude --dangerously-skip-permissions "$@"
