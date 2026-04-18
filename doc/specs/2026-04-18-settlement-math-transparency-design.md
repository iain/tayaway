# Settlement-math transparency

## Problem

On the event expenses page, the Settlement Preview modal and locked settlement
cards show a bare list of transfers ("Alice → Bob €30"). Users cannot verify
that these transfers are correct, minimal, or even accurate — the output of
`minimizeTransfers` is opaque. When users are about to send real money, or
when they return later to audit a past settlement, they need to see the
reasoning: **the net balances that led to these transfers, and how each
transfer reduces those balances**.

This undermines trust. It's also the single change with the highest impact on
"can I trust the numbers?" for the expenses feature, per the critique round
that preceded this spec.

## Goal

Reveal the settlement math in both the preview modal and on locked
settlement cards via a collapsed "Show math" expander. The math shows:

1. **Net balances** — who owes how much / is owed how much before settlement.
2. **Transfer derivation** — a one-line annotation under each transfer
   explaining what it settles, in plain English.

The work is intentionally scoped to the transfer derivation. The per-person
drilldown (clicking a name to see which expenses contributed to their share)
is a separate feature tracked elsewhere.

## Non-goals

- No per-expense breakdown inside the math panel — that belongs to the
  per-person audit view.
- No change to the `minimizeTransfers` algorithm itself. Only its output is
  being made legible.
- No changes to the Cost Split table at the top of the expenses page.
- No new data persisted to the backend. No migration.

## User-facing design

### Expander placement

A collapsed disclosure ("Show math" / "Hide math") appears:

- **Settlement Preview modal**: between the "N expenses will be locked" line
  and the transfer list.
- **Each locked settlement card**: inside the gray header row, adjacent to
  "Settled by X on …".

Default state: collapsed everywhere. The expander's open/closed state does
not persist across page loads.

### Expanded content

When expanded, two sub-sections render in order:

1. **Net balances** panel

   One row per person with a non-zero net balance (people who are already
   even are omitted). Each row:

   ```
   Alice    is owed €30.00     (green, positive-for-user color)
   Bob      owes €40.00        (red, negative-for-user color)
   ```

   Ordered: creditors first (largest amount-owed-to-them descending), then
   debtors (largest amount-they-owe descending). This matches how the reader
   naturally scans "who needs to be paid" → "who owes".

2. **Transfers with annotations**

   The existing transfer list gains one line of grey subtext under each row:

   ```
   Bob → Dave            €40.00
     Clears Bob's balance · Dave now even
   Carol → Alice         €30.00
     Clears Carol's balance · Alice now even
   ```

   Annotation wording is produced by a pure function from `(transfer,
preBalances)` — see _Annotation logic_ below.

### Edge cases

- **Zero transfers** (everyone already even): the expander does not render at
  all. The existing "All balances are settled — no transfers needed." message
  continues to show in the preview.
- **Rounding drift**: if balance sums differ from zero by more than €0.01, a
  small amber `⚠ Rounding drift €X` row appears below the balances panel.
  Drift within €0.01 is floored to zero silently.
- **Deleted member / missing name**: fall back to email, then to `Unknown`.
  Reuses the existing `getMemberName` utility.

## Data source

### Preview

Computed from current expenses + RSVPs using the existing
`computeBalances(unsettledExpenses, attendingRsvps, eventStart, eventEnd,
resolveParticipant)` util. This is what `previewTransfers` already consumes;
we'll just surface the intermediate balances to the UI too, alongside the
transfers.

### Locked settlement

**Balances are derived from the stored transfers themselves**, not recomputed
from expenses or RSVPs. For each user:

```
balance = Σ(transfer.amount where from=user) − Σ(transfer.amount where to=user)
```

This is self-consistent by construction: the transfers encode exactly what
was settled, so summing them back is guaranteed to match the annotations and
not drift if RSVPs change later.

Recomputing from RSVPs is explicitly rejected because RSVPs can change after
a settlement is locked — recomputation would then disagree with the transfers
the user already sent money for. Deriving from transfers is also cheaper (no
need to load all the locked expenses just to show math).

**No new backend fields, no migration.** `Settlement` and `SettlementTransfer`
already flow through the object pool.

## Annotation logic (pure function)

```
annotateTransfer(transfer, preBalances) → string
```

Given a single transfer and the map of balances _immediately before this
transfer is applied_ (i.e. the running balances after all prior transfers),
produce the annotation string by combining a "from side" phrase and a "to
side" phrase with `·`.

**From side** (based on `preBalances[transfer.from]` and `transfer.amount`):

- If balance equals transfer amount: `"Clears {from}'s balance"`
- If balance exceeds transfer amount: `"Settles €{amount} of {from}'s €{balance}"`
- (Balance less than transfer amount shouldn't happen — minimizeTransfers
  caps transfer at min of debtor and creditor. If it does happen, treat as
  "Clears {from}'s balance".)

**To side** (based on `|preBalances[transfer.to]|` and `transfer.amount`):

- If creditor amount equals transfer amount: `"{to} now even"`
- If creditor amount exceeds transfer amount: `"{to} still owed €{remaining}"`

Joined: `"{fromPhrase} · {toPhrase}"`.

The function is driven off a **simulated running balance** — the caller walks
the transfer list in order, applying each transfer to the map, so the "before"
state used for annotation reflects prior transfers. This matches the greedy
algorithm's actual sequencing and produces annotations that are consistent
with what a user would compute mentally, step by step.

## Components and files

New:

- `frontend/src/components/expenses/SettlementMath.vue` — shared
  presentational component. Props: `{ balances: Balance[], transfers:
AnnotatedTransfer[], roundingDrift?: number }`. Renders the expander's
  internal content. The expander toggle itself (button + state) lives in the
  parent so preview and locked card can style/place it to fit their chrome.
- `frontend/src/components/expenses/SettlementMath.spec.ts` — component tests.

Modified:

- `frontend/src/utils/settlement.ts` — add two pure functions:
  - `deriveBalancesFromTransfers(transfers: SettlementTransfer[]): Map<userId, number>`
  - `annotateTransfers(transfers, initialBalances): AnnotatedTransfer[]` —
    walks the list, computing running balances, returning each transfer
    paired with its annotation string and from/to pre-balance for display.
- `frontend/src/utils/settlement.spec.ts` — unit tests for the two new
  functions (see _Testing_ below).
- `frontend/src/components/expenses/SettlementSection.vue` — wire the
  expander into both the preview modal and the per-settlement card header.
  Add local `ref` for each expander's open/closed state (preview has one
  ref; each locked card needs its own keyed by settlement id).
- `e2e/tests/expenses.spec.ts` — one E2E flow (see _Testing_).

## Testing

### Unit (`settlement.spec.ts`)

- `deriveBalancesFromTransfers`:
  - Empty list → empty map.
  - Single transfer → two entries with equal and opposite balances.
  - Multi-party case from this spec (Alice/Bob/Carol/Dave) → exact
    reconstruction.
  - Round-trip: `computeBalances → minimizeTransfers → deriveBalancesFromTransfers`
    equals original `computeBalances` output (within €0.01).
- `annotateTransfers`:
  - "Clears X's balance · Y now even" — symmetric clear.
  - "Settles €A of X's €B · Y now even" — partial from side, full to side.
  - "Clears X's balance · Y still owed €C" — full from side, partial to side.
  - "Settles €A of X's €B · Y still owed €C" — partial both sides.
  - Running balance correctness: two chained transfers where the second's
    annotation depends on the first's effect.

### Component (`SettlementMath.spec.ts`)

- Zero transfers: component renders nothing (or renders empty and parent
  hides).
- Renders balance rows in creditor-then-debtor order, creditors shown as
  "is owed", debtors as "owes".
- Renders annotation subtext under each transfer.
- Rounding-drift row renders when drift > €0.01, hidden otherwise.

### E2E (`expenses.spec.ts`)

One new flow:

1. Seed event with 4 attending users and expenses that produce the
   Alice/Bob/Carol/Dave scenario.
2. Open Start Settlement → expand "Show math" → assert balances panel rows
   and transfer annotations match expected strings.
3. Confirm settlement.
4. Expand "Show math" on the now-locked settlement card → assert the same
   balances and annotations appear, proving locked-card derivation matches
   the preview.

## Risk and rollout

- Pure-frontend change, no migration, no backend deploy dependency.
- Feature is additive: default-collapsed expander means users who never
  open it see exactly the current UI.
- If `annotateTransfers` has a bug, worst case is incorrect-sounding
  subtext. The transfer amounts themselves are unchanged and come from the
  same `minimizeTransfers` output as today.

## Open questions

None. Toggle wording ("Show math" / "Hide math") is a starting point and
can be tweaked during implementation if something clearer emerges.
