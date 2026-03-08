---
description: Run tests, fix all failures/warnings, repeat until clean
allowed-tools: Bash(mise:*), Read, Edit, Write, Glob, Grep
---

# Fix — Run tests and fix all issues

Run `mise run fix`, then analyse every failure, deprecation warning, and compiler
diagnostic in the output. Fix each issue in the source code. Repeat until the suite
passes with a clean output.

## Instructions

Work through the following loop:

1. **Run with auto-fix**

   ```
   mise run fix
   ```

   This applies all auto-correctable fixes (formatting etc.) before running the full
   suite, so only genuine failures remain. Capture the full output.

2. **Analyse the output** — identify all of the following:
   - Test failures (assertion errors, exceptions, unexpected results)
   - Type errors (TypeScript or Sorbet diagnostics)
   - Lint errors and warnings (ESLint, RuboCop)
   - Any other diagnostics that indicate the code is not in ideal shape

3. **Fix every issue found**
   - Read the relevant source files before editing them.
   - Apply the minimal correct fix. Do not refactor unrelated code.
   - If a test is wrong (not the implementation), fix the test.
   - After fixing, briefly state what you changed and why.

4. **Run `mise run fix` again.** If the output is clean (zero failures, zero warnings),
   stop and report success. Otherwise, go back to step 2.

## Rules

- Never skip a warning. Treat every warning and every deprecation as a failure that must
  be resolved.
- Fix every issue in the output, even if it pre-dates recent changes. If the suite reports
  it, it needs to be fixed.
- Never silence a warning with inline disable comments unless the only correct fix is to
  suppress it.
- Keep fixes minimal — only change what is needed to resolve the specific issue.
- Always fix the root cause, not the symptom. Do not add workarounds, type casts, or
  assertions just to make a diagnostic go away — understand why it's happening and correct
  the underlying code.
- Follow all rules in CLAUDE.md.
- If the same error reappears after a fix, stop and reason carefully about the root cause
  before trying again — do not enter an infinite retry loop.
- If after three iterations you cannot resolve an issue, stop and explain the blocker to
  the user clearly.
