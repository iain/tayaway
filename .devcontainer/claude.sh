#!/bin/bash
# Start a devcontainer and run Claude Code with no permission prompts.
# Usage: .devcontainer/claude.sh [args...]
set -e

source "$(dirname "$0")/start.sh"

devcontainer exec --workspace-folder "$WORKSPACE" \
  claude --dangerously-skip-permissions "$@"
