#!/bin/bash
# Run a command inside the devcontainer, starting it if needed.
# Usage: .devcontainer/exec.sh [command] [args...]
set -e

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"

if [ -z "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
  CLAUDE_CODE_OAUTH_TOKEN="$(security find-generic-password -s claude-code -w 2>/dev/null)" || true
fi
export CLAUDE_CODE_OAUTH_TOKEN

devcontainer up --workspace-folder "$WORKSPACE" >/dev/null 2>&1

if [ $# -eq 0 ]; then
  devcontainer exec --workspace-folder "$WORKSPACE" fish
else
  devcontainer exec --workspace-folder "$WORKSPACE" "$@"
fi
