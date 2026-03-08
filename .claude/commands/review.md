---
description: Audit recent changes across correctness, reliability, security, and more
allowed-tools: Bash(git:*), Agent, AskUserQuestion
---

# Review

## Context

- Current branch: !`git branch --show-current`
- Latest commit: !`git log --oneline -1`
- Diff to review: !`git diff HEAD~1...HEAD`
- Changed files: !`git diff HEAD~1...HEAD --name-only`
- Recent commits: !`git log --oneline -10`
- Project conventions: !`cat CLAUDE.md`

## Severity definitions

Use these definitions consistently when classifying findings:

- **Critical** — must be fixed before merge/deploy: bugs, security holes, data integrity
  risks, or anything that could cause data loss or a production outage.
- **Major** — significant issues that should be addressed; context and trade-offs may
  influence the decision, but the default expectation is that they are resolved.
- **Minor** — real issue worth fixing, not blocking: convention violations, missing
  edge-case tests, suboptimal patterns.
- **Suggestion** — low-priority or forward-looking: ideas for future improvement.

## Instructions

### Step 0 — Determine scope

Review the most recent commit on the current branch. State what you are reviewing at the
top of the output.

### Step 1 — Launch 8 audit agents in parallel

Spawn all 8 agents simultaneously using the Agent tool. Pass each agent:

- The full diff
- The list of changed files
- The commit message
- The contents of CLAUDE.md (project conventions)
- The severity definitions from this command
- This technology context: **Ruby 4 + Roda + Sequel + Falcon + Sorbet (backend) /
  Vue 3 + TypeScript + Vite + Tailwind CSS + Pinia (frontend) / PostgreSQL /
  real-time sync via WebSockets + LISTEN/NOTIFY / RSpec + Vitest + Playwright**
- An instruction to **read relevant source files** before drawing conclusions — do not
  rely solely on the diff; read the full context of changed functions, their callers, and
  related tests. Available tools: Read, Grep, Glob, Bash.

Each agent must return a structured list of findings. For each finding, include:

- Severity (`critical`, `major`, `minor`, or `suggestion`)
- Audit dimension in brackets, e.g. `[Correctness]`
- A concise description of the issue
- File and approximate line number where applicable
- A recommended fix or action

If no issues are found, return: `[DimensionName] No findings.`

---

**Agent 1 — Correctness**

Read the changed source files in full before forming any conclusions.

- **End-to-end path tracing**: for each new or modified endpoint or operation, trace the
  complete flow from HTTP request → validation → service logic → database → response. Does
  the implementation actually do what the commit/PR claims?
- **HTTP status codes**: are 200/201/400/404 returned in the right situations? Check error
  paths as carefully as success paths.
- **Response contract**: are the right fields returned in the right shape? Is the response
  consistent with existing endpoint conventions?
- **Regression risk**: does any change to shared code or services break existing behaviour
  that isn't covered by the modified tests? Read callers of changed functions to assess
  blast radius.
- **Edge cases**: empty or null inputs, missing records, boundary values, off-by-one errors.
- **Concurrent writes**: race conditions, lost updates, TOCTOU hazards.
- **Business rules**: are domain invariants enforced consistently across all code paths,
  including error paths and partial failures?
- **Real-time sync**: does the change call `Broadcaster.object_changed` /
  `Broadcaster.object_deleted` after every mutation so WebSocket clients stay in sync?

---

**Agent 2 — Reliability**

Read the changed source files in full before forming any conclusions.

- **Failure modes**: what happens when the database is unavailable or a query times out?
  Is the error surfaced meaningfully?
- **Transactions**: are multi-table writes wrapped in a transaction so a partial failure
  cannot leave data inconsistent?
- **Idempotency**: are operations that should be idempotent actually implemented correctly?
- **Result monad**: do services use the Result monad (Success/Failure with bind chains)
  correctly? Are error cases propagated, not swallowed?
- **Error context**: are errors propagated with enough information to be diagnosed?

---

**Agent 3 — Security**

Read the changed source files in full before forming any conclusions.

- **Authentication and authorisation**: are all new endpoints gated appropriately? Are
  there missing auth checks that allow privilege escalation?
- **IDOR**: can a caller access another user's or workspace's resources by supplying a
  different ID? Is workspace membership validated?
- **Input validation**: is all data validated at system boundaries? Are there injection
  risks (SQL via raw queries, XSS, command injection)?
- **Information disclosure**: do error responses leak internal details?
- **Secrets**: are secrets hardcoded, logged, or included in API responses? (IBAN is
  owner-only via `/api/auth/me`, never broadcast.)
- **Mass assignment**: can a caller set fields they should not by over-posting?

---

**Agent 4 — Observability**

Read the changed source files in full before forming any conclusions.

- **Logging**: are new operations logged at appropriate levels?
- **Sensitive data in logs**: does any log statement risk writing PII, tokens, or secrets?
- **Silent failures**: are there operations whose failures would not surface in logs?
- **Diagnosability**: given only the logs this code would produce, could a developer
  diagnose an incident?

---

**Agent 5 — Operability**

Read the changed source files in full before forming any conclusions.

- **Zero-downtime deploy**: can this be deployed without downtime?
- **Rollback safety**: if the deployment is reverted, will the previous version work
  correctly against the updated database schema?
- **Migration safety**: inspect any new Sequel migration files. Are changes additive-only?
  Do any operations take locks that would block writes on a live table?
- **New configuration**: does the change require new environment variables or secrets?
  Are defaults safe?

---

**Agent 6 — Performance Under Load**

Read the changed source files in full before forming any conclusions.

- **Unbounded result sets**: can any query return an unbounded number of rows?
- **Index coverage**: do new queries filter or sort on columns with appropriate indexes?
- **N+1 queries**: is related data loaded inside a loop instead of a single query?
- **Bulk operations**: are multiple writes done one at a time instead of batched?
- **Hot-path cost**: are expensive operations performed inside loops that could be hoisted?

---

**Agent 7 — Testability**

Read the changed source files and the test files in full before forming any conclusions.

- **Critical path coverage**: do tests cover the primary scenarios introduced or changed?
- **Failure and edge case coverage**: do tests cover error paths, boundary values, and
  invalid inputs?
- **Test isolation**: do tests share state that could cause ordering-dependent failures?
- **Regression value**: do the tests actually catch regressions, or do they only assert
  the current behaviour without verifying correctness?
- **Determinism**: are tests free of wall-clock time or random data that could cause flakes?
- **Uncovered branches**: are there new code branches with no corresponding test?

---

**Agent 8 — Code Maintainability**

Read CLAUDE.md and the changed source files in full before forming any conclusions.

- **Project conventions**: verify the change follows all rules in CLAUDE.md — naming,
  code style, architectural patterns (Result monad, object pool, PoolSerializer, etc.).
- **Dead code**: does the diff leave behind unused methods, variables, or imports?
- **Magic values**: are there hardcoded strings or numbers that should be named constants?
- **Abstraction justified**: are new helpers used in more than one place, or do they add
  complexity for a single call site?
- **Object pool sync**: if a new object type is added, is it registered in both
  `object_registry.rb` and `types/pool.ts`? Is CLAUDE.md updated?
- **Naming**: do functions and variables have names that describe what they do?
- **Readability**: are non-obvious decisions explained? Could a new developer understand
  the change?
- **Documentation**: is CLAUDE.md or other documentation updated where the change affects
  commands, configuration, architecture, or conventions?

---

### Step 2 — Aggregate and report

Collect all findings from all 8 agents. Deduplicate any finding that appears in more than
one agent's output — keep the sharper description. Then produce the report:

```
## Review: <commit summary>

### Critical
<findings>

### Major
<findings>

### Minor
<findings>

### Suggestions
<findings>

### Verdict
Approve | Approve with minor fixes | Request changes
<one or two sentences>
```

For each finding, include the dimension tag (e.g. `[Correctness]`), a concise description,
and a file:line reference where applicable. Omit any severity tier that has no findings.
