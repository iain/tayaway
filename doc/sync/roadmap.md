# Sync Engine v2: roadmap

**Sync Engine v2** is the project that takes the current engine to the one described in [spec.md](spec.md). This is its plan, agreed 2026-11-28.

## Steps

1. **Coverage tooling.** Tag conventions and the report script (see [Coverage](spec.md#coverage)). Then turn [bugs-to-verify.md](bugs-to-verify.md) into expected-failure tests, which also exercises the tooling.
2. **Decisions.** Record the default answers to the easy open questions in the spec, marked as revisitable. Write a short design document for *the protocol redesign* covering the connected one-way doors (`OQ-1`, `OQ-2`, `OQ-3`, `OQ-14`), and get it signed off before writing code. See [Proposed answers](spec.md#proposed-answers).
3. **Gap inventory.** Complete it through the coverage report (below), then work through the gaps by workstream.

## Gap inventory

The gap inventory and the coverage report are the same thing, so there is no separate list to keep up to date.

### Statuses

Every spec ID has one status:

| Status | Meaning | How it shows up |
|---|---|---|
| Covered | A tagged test passes | Tagged passing test |
| Known gap | The guarantee is known not to hold | Tagged test marked as expected to fail: RSpec `pending`, Vitest `it.fails`, Playwright `test.fail()` |
| Believed met | Code reading says it holds, but there is no test | Listed in the report's annotations |
| Unknown | Not investigated yet | No tag, no annotation |
| Blocked | Can't be tested until an open question is decided | Placeholder test referencing the `OQ-n` |

Expected-failure tests count as gaps, not coverage. When a fix makes one pass, the expected-failure marker makes the run fail until the marker is removed, so the inventory updates itself.

### Filling it in

From the cheapest evidence up:

1. Tag existing tests that already prove a guarantee.
2. Turn the suspected bugs into expected-failure tests.
3. Read the code for the remaining IDs; record *Believed met* or *Unknown*.
4. Write probe tests for *Believed met* and *Unknown* until each is *Covered* or a *Known gap*.

### Workstreams

Gaps are grouped by the architectural change that closes them, not by guarantee: one change often closes many. Expected workstreams:

- **Cursor and confirmation** (the protocol redesign): `SYNC-G-302`, `308`, `309`, `311`, `312`, `316`, `318`, `403`, `407`, and others.
- **Mutation model** (intent, base values, replay): `SYNC-G-107`, `113`, `404`, `405`, `408`, `504`.
- **Local storage and users**: `SYNC-G-105`, `106`, `108`, `901`.
- **Visibility**: `SYNC-G-701`, `702`, `704`, `705`.
- **Transparency API**: the 10xx guarantees.
- **Operations**: the 11xx guarantees.

Priority order: data loss (`SYNC-P-3`) first, then silent incorrectness, then transparency, then operations.

## Test suite

Start now, before the open questions are decided. Most guarantees are testable without them, and each gap starts as a failing test. Only tests that depend on an undecided number or mechanism wait, as *Blocked* placeholders.

### No Cucumber

Scenarios are written as Playwright tests, not Gherkin:

- The spec is already the human-readable layer; Gherkin would add a third copy of each scenario (spec, feature file, step definitions) to maintain.
- The scenarios involve several clients, going offline, dropped responses and fake clocks, which read better as code with fixtures than as step definitions.
- Playwright gives the same structure: the test title is the scenario title, the tag is `@SYNC-S-nnn`, and `test.step('given …')` / `test.step('when …')` / `test.step('then …')` read like Gherkin.

The investment goes into reusable fixtures instead: `twoClients`, `goOffline()`, `dropNextResponse()`, `stallWebSocket()`, `skewClock()`.
