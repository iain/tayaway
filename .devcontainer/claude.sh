#!/bin/bash
# Start a devcontainer and run Claude Code with no permission prompts.
# Usage: .devcontainer/claude.sh [args...]
set -e

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"

# Pull OAuth token from macOS Keychain if not already set
if [ -z "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
  CLAUDE_CODE_OAUTH_TOKEN="$(security find-generic-password -s claude-code -w 2>/dev/null)" || true
fi
export CLAUDE_CODE_OAUTH_TOKEN

devcontainer up --workspace-folder "$WORKSPACE" >/dev/null 2>&1

devcontainer exec --workspace-folder "$WORKSPACE" \
  claude --dangerously-skip-permissions "$@"
