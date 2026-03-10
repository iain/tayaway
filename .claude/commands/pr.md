---
description: Create a pull request from the current branch
allowed-tools: Bash(git:*), Bash(gh:*)
---

# Create Pull Request

## Context

- Current branch: !`git branch --show-current`
- Base branch: !`git log --oneline main..HEAD 2>/dev/null | tail -1 && echo "---" && git log --oneline -1`
- All commits on this branch: !`git log --oneline main..HEAD`
- Full diff against main: !`git diff main...HEAD --stat`

## Instructions

### Step 1 — Preflight checks

1. Verify the current branch is **not** `main`. If it is, stop and tell the user to create
   a feature branch first.
2. Run `git status --short`. If there are uncommitted changes, stop and suggest running
   `/commit` first.
3. Check if the branch has a remote tracking branch: `git rev-parse --abbrev-ref @{u}`.
   If not, push with `git push -u origin HEAD`.
4. If the branch is ahead of its remote, push with `git push`.

### Step 2 — Analyse changes

Read the full diff (`git diff main...HEAD`) and all commit messages (`git log main..HEAD`).
Understand the purpose, scope, and impact of the changes.

### Step 3 — Create the PR

Run `gh pr create` with:

- **Title**: short, imperative, title case (under 70 characters). Match the commit message
  style if there's a single commit.
- **Body**: use this template via HEREDOC:

```
gh pr create --title "<title>" --body "$(cat <<'EOF'
## Summary

<1-3 bullet points describing what changed and why>

## Test plan

<bulleted checklist of how to verify the changes>
EOF
)"
```

### Step 4 — Report

Print the PR URL so the user can open it.

## Rules

- Never create a PR from `main`
- Never push with `--force`
- Keep the title concise — details go in the body
- If there are multiple unrelated commits, mention that in the summary
- If the branch has already been pushed and a PR already exists, tell the user and print
  the existing PR URL instead of creating a duplicate
