---
description: Run tests then commit — prompts if changes are mixed
allowed-tools: Bash(mise:*), Bash(git:*)
---

# Commit

## Context

- Unstaged + staged changes: !`git diff HEAD`
- Untracked files: !`git status --short`
- Recent commits (for message style): !`git log --oneline -8`

## Instructions

### Step 1 — Run tests

Run `mise run fix`. If tests fail, stop and report the failures. Do not commit.

### Step 2 — Assess the changes

Read the diff carefully. Decide whether the changes form **one cohesive unit** (single
concern, single feature, single fix) or **multiple unrelated concerns**.

- If cohesive: proceed directly to Step 3 with a single commit. Do not ask.
- If mixed: ask the user once — "These changes cover multiple concerns. One commit or
  separate commits?" — then follow their answer.

### Step 3 — Commit

For each commit:

1. Stage only the files that belong to it (`git add <files…>`).
2. Write a commit message that is **short, imperative, title case** (capitalise each
   significant word), easy to scan in a `git log --oneline`. Examples:
   `Add Pagination to Events Endpoint`, `Fix Null Check in Vote Service`, `Bump Puma to 6.5`.
3. No bullet-point bodies, no "Co-Authored-By", no fluff. Just the subject line unless a
   single sentence of context is genuinely needed (rare).
4. Run `git commit -m "<message>"`.

If the user asked for separate commits, repeat for each concern in a logical order.
