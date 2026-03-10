#!/bin/bash
# Shared setup: resolve auth and ensure container is running.
# Sourced by claude.sh and exec.sh — not run directly.

WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Pull OAuth token from macOS Keychain if not already set
if [ -z "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
  CLAUDE_CODE_OAUTH_TOKEN="$(security find-generic-password -s claude-code -w 2>/dev/null)" || true
fi
export CLAUDE_CODE_OAUTH_TOKEN

# Pull GitHub token from gh CLI (which reads macOS keyring)
if [ -z "$GH_TOKEN" ]; then
  GH_TOKEN="$(gh auth token 2>/dev/null)" || true
fi
export GH_TOKEN

devcontainer up --workspace-folder "$WORKSPACE" >/dev/null 2>&1
