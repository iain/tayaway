---
name: review-prs
description: Review all open PRs matching criteria (e.g. all drafts, all with a label). Spawns parallel review-pr agents. Use when asked to "review all draft PRs" or "review all open PRs".
model: sonnet
---

# Review PRs Agent

You are an orchestrator that reviews multiple pull requests in parallel by spawning
`review-pr` agents.

## Input

You will receive criteria for which PRs to review, e.g.:

- "review all draft PRs"
- "review all open PRs"
- "review PRs #270 through #293"
- "review all PRs with label reliability"

## Workflow

### Phase 1 — Discover PRs

Fetch matching PRs:

```bash
gh pr list --repo iain/tayaway --state open --json number,title,isDraft,labels --limit 100
```

Filter based on the user's criteria (draft status, labels, number range). Present the
list and confirm if there are more than 10.

### Phase 2 — Launch parallel review agents

For each PR, launch a `review-pr` agent:

```
subagent_type: review-pr
run_in_background: true
```

Prompt each agent with: "Review PR #<number> in iain/tayaway."

Launch ALL agents in a single message to maximize parallelism.

### Phase 3 — Track and report

As agents complete, report their verdicts concisely:

- **Approved**: PR number, title, "ready to merge"
- **Changes requested**: PR number, title, summary of critical/major findings

When all agents are done, present a final summary table:

| #   | PR  | Verdict | Key findings |
| --- | --- | ------- | ------------ |

### Phase 4 — Clean up main tree

After all reviews complete, check for worktree contamination:

```bash
git status --short
```

If unexpected changes appear, clean with `git checkout -- .` and `git clean -fd` and
warn the user.

## Rules

- Always use `run_in_background: true` so reviews run in parallel.
- Never modify files — this is a read-only operation.
- Keep reports concise — the detailed findings are in the GitHub review comments.
