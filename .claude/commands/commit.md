Create a git commit for the current staged and unstaged changes.

## Instructions

1. Run these commands in parallel to understand the current state:
   - `git status` to see all changed and untracked files
   - `git diff --cached` and `git diff` to see staged and unstaged changes
   - `git log --oneline -5` to see recent commit message style
2. Analyze all changes and determine what should be committed:
   - Do not commit files that likely contain secrets (`.env`, credentials, tokens)
   - If there are no changes to commit, inform the user and stop
3. If there are unstaged changes or untracked files, ask the user which files to include
4. Stage the selected files with `git add` (use specific file paths, not `-A` or `.`)
5. Draft a concise commit message:
   - Follow the style of recent commits in the repo
   - Focus on the "why" rather than the "what"
   - Use imperative mood (e.g., "Add feature" not "Added feature")
   - Keep the first line under 72 characters
6. Create the commit using a HEREDOC for the message:

   ```
   git commit -m "$(cat <<'EOF'
   Commit message here.

   Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
   EOF
   )"
   ```

7. Run `git status` after the commit to verify success

## Important

- Always read the diff before composing the commit message — never guess at what changed
- Never amend an existing commit unless explicitly asked
- Never push to a remote unless explicitly asked
- Never use `git add -A` or `git add .` — always add specific files
- If a pre-commit hook fails, fix the issue and create a NEW commit (do not use `--amend`)
