#!/bin/bash
# Run a command inside the devcontainer, starting it if needed.
# Usage: .devcontainer/exec.sh [command] [args...]
set -e

# shellcheck disable=SC1091
source "$(dirname "$0")/start.sh"

if [ $# -eq 0 ]; then
  devcontainer exec --workspace-folder "$WORKSPACE" fish
else
  devcontainer exec --workspace-folder "$WORKSPACE" "$@"
fi
