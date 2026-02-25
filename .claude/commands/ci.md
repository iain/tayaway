Run the full CI suite and fix all issues until it passes cleanly.

## Instructions

1. Run `mise run ci` and wait for it to complete.
2. Examine the output carefully for any failures, errors, or warnings — including lint errors, type errors, test failures, and e2e failures.
3. If there are any issues:
   a. Analyze the root cause of each failure.
   b. Fix the issues in the source code.
   c. Go back to step 1 and run `mise run ci` again.
4. Repeat this loop until `mise run ci` passes with zero failures, errors, and warnings.
5. When everything passes, report a summary of what was fixed.

## Important

- Fix the actual problems — do not suppress warnings, disable lint rules, or skip tests.
- If a fix touches backend code, ensure Ruby style (`# typed: true`, `# frozen_string_literal: true`, double quotes) is preserved.
- If a fix touches frontend code, ensure TypeScript/Vue conventions (`<script setup lang="ts">`, no semicolons) are preserved.
- If you are unsure about the correct fix for a failure, ask the user before proceeding.
