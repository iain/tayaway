#!/bin/bash
# Runs targeted tests after Claude edits a file.
# Only runs if the edited file has a corresponding test file.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -z "$FILE_PATH" ] && exit 0

PROJECT_DIR="$CLAUDE_PROJECT_DIR"

if [[ "$FILE_PATH" == *"backend/"*".rb" && "$FILE_PATH" != *"_spec.rb" ]]; then
  # Backend source file — find corresponding spec
  SPEC=$(echo "$FILE_PATH" | sed "s|app/|spec/|" | sed "s|\.rb$|_spec.rb|")
  if [ -f "$SPEC" ]; then
    cd "$PROJECT_DIR/backend" && RACK_ENV=test bundle exec rspec "$SPEC" --format progress 2>&1
  fi
elif [[ "$FILE_PATH" == *"_spec.rb" ]]; then
  # Backend spec file — run it directly
  cd "$PROJECT_DIR/backend" && RACK_ENV=test bundle exec rspec "$FILE_PATH" --format progress 2>&1
elif [[ "$FILE_PATH" == *"frontend/src/"* && "$FILE_PATH" != *".spec."* ]]; then
  # Frontend source file — find corresponding spec
  SPEC=$(echo "$FILE_PATH" | sed "s|\.ts$|.spec.ts|" | sed "s|\.vue$|.spec.ts|")
  if [ -f "$SPEC" ]; then
    cd "$PROJECT_DIR/frontend" && pnpm exec vitest run "$SPEC" 2>&1
  fi
elif [[ "$FILE_PATH" == *".spec."* ]]; then
  # Frontend spec file — run it directly
  cd "$PROJECT_DIR/frontend" && pnpm exec vitest run "$FILE_PATH" 2>&1
fi

exit 0
