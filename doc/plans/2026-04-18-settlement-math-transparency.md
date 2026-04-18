# Settlement-math transparency implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reveal the math behind a settlement (net balances + per-transfer annotations) via a collapsed "Show math" expander on both the Settlement Preview modal and each locked settlement card, so users can trust and audit the numbers.

**Architecture:** Two new pure functions in `frontend/src/utils/settlement.ts` (`deriveBalancesFromTransfers`, `annotateTransfers`) feed a new shared `SettlementMath.vue` component. `SettlementSection.vue` wires an expander toggle in two places — the preview consumes `computeBalances` output; each locked card derives balances from its own stored transfers. No backend changes, no migration.

**Tech Stack:** Vue 3 `<script setup lang="ts">`, Pinia, Vitest, Playwright, Tailwind CSS.

**Spec:** `doc/specs/2026-04-18-settlement-math-transparency-design.md`

---

## File Structure

**Create**

- `frontend/src/components/expenses/SettlementMath.vue` — presentational component rendering balances panel + annotated transfer list.
- `frontend/src/components/expenses/SettlementMath.spec.ts` — component tests.

**Modify**

- `frontend/src/utils/settlement.ts` — add `Balance`, `AnnotatedTransfer` types and `deriveBalancesFromTransfers`, `annotateTransfers` pure functions.
- `frontend/src/utils/settlement.spec.ts` — add unit tests for both new functions.
- `frontend/src/components/expenses/SettlementSection.vue` — add expander toggle in preview modal and in each locked settlement card header; render `SettlementMath.vue` inside each expander.
- `e2e/tests/settlements.spec.ts` — add one UI test that opens the preview, expands the math, confirms the settlement, and re-expands the math on the locked card.

Each task below ends in a commit so progress is always pushable.

---

### Task 1: Add `deriveBalancesFromTransfers` pure function

**Files:**

- Modify: `frontend/src/utils/settlement.ts`
- Test: `frontend/src/utils/settlement.spec.ts`

- [ ] **Step 1: Append failing tests to `settlement.spec.ts`**

At the bottom of `frontend/src/utils/settlement.spec.ts`, add:

```typescript
import {
  computeBalances,
  minimizeTransfers,
  deriveBalancesFromTransfers,
} from './settlement'

// …existing describe blocks stay as-is…

describe('deriveBalancesFromTransfers', () => {
  it('returns empty map for empty transfer list', () => {
    expect(deriveBalancesFromTransfers([])).toEqual(new Map())
  })

  it('produces equal and opposite balances for a single transfer', () => {
    const balances = deriveBalancesFromTransfers([
      { fromUserId: 'bob', toUserId: 'alice', amount: 50 },
    ])
    expect(balances.get('bob')).toBe(50)
    expect(balances.get('alice')).toBe(-50)
  })

  it('sums balances across multiple transfers', () => {
    const balances = deriveBalancesFromTransfers([
      { fromUserId: 'bob', toUserId: 'dave', amount: 40 },
      { fromUserId: 'carol', toUserId: 'alice', amount: 30 },
    ])
    expect(balances.get('alice')).toBe(-30)
    expect(balances.get('bob')).toBe(40)
    expect(balances.get('carol')).toBe(30)
    expect(balances.get('dave')).toBe(-40)
  })

  it('accumulates when the same user appears in several transfers', () => {
    const balances = deriveBalancesFromTransfers([
      { fromUserId: 'charlie', toUserId: 'alice', amount: 30 },
      { fromUserId: 'charlie', toUserId: 'bob', amount: 20 },
    ])
    expect(balances.get('charlie')).toBe(50)
    expect(balances.get('alice')).toBe(-30)
    expect(balances.get('bob')).toBe(-20)
  })

  it('round-trips with computeBalances + minimizeTransfers', () => {
    const start = '2026-07-01'
    const end = '2026-07-07'
    const expenses = [
      { userId: 'alice', startDate: start, endDate: end, amount: 60 },
      { userId: 'bob', startDate: start, endDate: end, amount: 40 },
    ]
    const rsvps = [
      { userId: 'alice', startDate: null, endDate: null },
      { userId: 'bob', startDate: null, endDate: null },
      { userId: 'carol', startDate: null, endDate: null },
    ]
    const original = computeBalances(expenses, rsvps, start, end)
    const transfers = minimizeTransfers(original)
    const derived = deriveBalancesFromTransfers(transfers)

    for (const [userId, amount] of original) {
      expect(derived.get(userId) ?? 0).toBeCloseTo(amount, 2)
    }
  })

  it('handles null fromUserId or toUserId by skipping that side', () => {
    const balances = deriveBalancesFromTransfers([
      { fromUserId: null, toUserId: 'alice', amount: 10 },
      { fromUserId: 'bob', toUserId: null, amount: 5 },
    ])
    expect(balances.get('alice')).toBe(-10)
    expect(balances.get('bob')).toBe(5)
  })
})
```

- [ ] **Step 2: Run the new suite and confirm it fails**

Run:

```
cd frontend && pnpm exec vitest run src/utils/settlement.spec.ts
```

Expected: failure importing `deriveBalancesFromTransfers` (not yet exported).

- [ ] **Step 3: Implement the function in `settlement.ts`**

At the bottom of `frontend/src/utils/settlement.ts`, below `minimizeTransfers`:

```typescript
/**
 * Derive net balances from a list of transfers.
 * For each user: balance = Σ(sent) − Σ(received).
 * Positive balance means user owes money; negative means user is owed.
 * Matches the sign convention used by computeBalances.
 */
export function deriveBalancesFromTransfers(
  transfers: Array<{
    fromUserId: string | null
    toUserId: string | null
    amount: number
  }>
): Map<string, number> {
  const balances = new Map<string, number>()

  for (const t of transfers) {
    if (t.fromUserId) {
      balances.set(t.fromUserId, (balances.get(t.fromUserId) ?? 0) + t.amount)
    }
    if (t.toUserId) {
      balances.set(t.toUserId, (balances.get(t.toUserId) ?? 0) - t.amount)
    }
  }

  for (const [userId, amount] of balances) {
    const rounded = Math.round(amount * 100) / 100
    if (Math.abs(rounded) < 0.005) {
      balances.delete(userId)
    } else {
      balances.set(userId, rounded)
    }
  }

  return balances
}
```

- [ ] **Step 4: Run the suite and confirm all pass**

Run:

```
cd frontend && pnpm exec vitest run src/utils/settlement.spec.ts
```

Expected: all existing tests still pass, plus the 6 new `deriveBalancesFromTransfers` tests pass.

- [ ] **Step 5: Commit**

```
git add frontend/src/utils/settlement.ts frontend/src/utils/settlement.spec.ts
git commit -m "Derive net balances from stored settlement transfers

Locked settlement cards need to show the balances that led to their
transfers, but RSVPs may have changed since the settlement was created.
Deriving from the transfers themselves is self-consistent by construction
and avoids loading locked expenses just to display math."
```

---

### Task 2: Add `annotateTransfers` pure function

**Files:**

- Modify: `frontend/src/utils/settlement.ts`
- Test: `frontend/src/utils/settlement.spec.ts`

- [ ] **Step 1: Append failing tests to `settlement.spec.ts`**

```typescript
import {
  computeBalances,
  minimizeTransfers,
  deriveBalancesFromTransfers,
  annotateTransfers,
} from './settlement'

// …keep previous describes…

describe('annotateTransfers', () => {
  const nameFor = (uid: string) =>
    ({ alice: 'Alice', bob: 'Bob', carol: 'Carol', dave: 'Dave' })[uid] ??
    'Unknown'

  it('returns empty list for empty input', () => {
    expect(annotateTransfers([], new Map(), nameFor)).toEqual([])
  })

  it('annotates a symmetric clear: "Clears X... · Y now even"', () => {
    const initial = new Map([
      ['bob', 40],
      ['dave', -40],
    ])
    const result = annotateTransfers(
      [{ fromUserId: 'bob', toUserId: 'dave', amount: 40 }],
      initial,
      nameFor
    )
    expect(result).toHaveLength(1)
    expect(result[0]!.annotation).toBe("Clears Bob's balance · Dave now even")
  })

  it('annotates partial from side: "Settles €A of X\'s €B · Y now even"', () => {
    const initial = new Map([
      ['bob', 50],
      ['dave', -40],
    ])
    const result = annotateTransfers(
      [{ fromUserId: 'bob', toUserId: 'dave', amount: 40 }],
      initial,
      nameFor
    )
    expect(result[0]!.annotation).toBe(
      "Settles €40.00 of Bob's €50.00 · Dave now even"
    )
  })

  it('annotates partial to side: "Clears X... · Y still owed €C"', () => {
    const initial = new Map([
      ['bob', 40],
      ['dave', -70],
    ])
    const result = annotateTransfers(
      [{ fromUserId: 'bob', toUserId: 'dave', amount: 40 }],
      initial,
      nameFor
    )
    expect(result[0]!.annotation).toBe(
      "Clears Bob's balance · Dave still owed €30.00"
    )
  })

  it('annotates partial both sides', () => {
    const initial = new Map([
      ['bob', 60],
      ['dave', -70],
    ])
    const result = annotateTransfers(
      [{ fromUserId: 'bob', toUserId: 'dave', amount: 50 }],
      initial,
      nameFor
    )
    expect(result[0]!.annotation).toBe(
      "Settles €50.00 of Bob's €60.00 · Dave still owed €20.00"
    )
  })

  it('walks running balances so later annotations reflect earlier transfers', () => {
    const initial = new Map([
      ['carol', 30],
      ['bob', 40],
      ['dave', -40],
      ['alice', -30],
    ])
    const result = annotateTransfers(
      [
        { fromUserId: 'bob', toUserId: 'dave', amount: 40 },
        { fromUserId: 'carol', toUserId: 'alice', amount: 30 },
      ],
      initial,
      nameFor
    )
    expect(result[0]!.annotation).toBe("Clears Bob's balance · Dave now even")
    expect(result[1]!.annotation).toBe(
      "Clears Carol's balance · Alice now even"
    )
  })

  it('handles null userIds by labelling them Unknown via nameFor fallback', () => {
    const initial = new Map<string, number>([['alice', -10]])
    const result = annotateTransfers(
      [{ fromUserId: null, toUserId: 'alice', amount: 10 }],
      initial,
      nameFor
    )
    expect(result[0]!.annotation).toContain('Alice now even')
  })

  it('preserves the original transfer fields alongside the annotation', () => {
    const initial = new Map([
      ['bob', 40],
      ['alice', -40],
    ])
    const result = annotateTransfers(
      [{ fromUserId: 'bob', toUserId: 'alice', amount: 40 }],
      initial,
      nameFor
    )
    expect(result[0]).toMatchObject({
      fromUserId: 'bob',
      toUserId: 'alice',
      amount: 40,
    })
  })
})
```

- [ ] **Step 2: Run and confirm failure**

Run:

```
cd frontend && pnpm exec vitest run src/utils/settlement.spec.ts
```

Expected: import error for `annotateTransfers`.

- [ ] **Step 3: Implement in `settlement.ts`**

Append below `deriveBalancesFromTransfers`:

```typescript
export interface AnnotatedTransfer {
  fromUserId: string | null
  toUserId: string | null
  amount: number
  annotation: string
}

/**
 * For each transfer, produce a human-readable "what this transfer did" string,
 * walking a simulated running balance so annotations reflect the effect of
 * prior transfers in the list.
 *
 * `nameFor` resolves a userId to a display name. Callers should pass a
 * fallback (e.g. "Unknown") for null/missing users.
 */
export function annotateTransfers(
  transfers: Array<{
    fromUserId: string | null
    toUserId: string | null
    amount: number
  }>,
  initialBalances: Map<string, number>,
  nameFor: (userId: string) => string
): AnnotatedTransfer[] {
  const running = new Map(initialBalances)
  const result: AnnotatedTransfer[] = []

  const EPS = 0.005

  for (const t of transfers) {
    const fromBalance = t.fromUserId ? (running.get(t.fromUserId) ?? 0) : 0
    const toBalance = t.toUserId ? (running.get(t.toUserId) ?? 0) : 0

    const fromName = t.fromUserId ? nameFor(t.fromUserId) : 'Unknown'
    const toName = t.toUserId ? nameFor(t.toUserId) : 'Unknown'

    // "From" side: debtor pays some or all of what they owe.
    const fromPhrase =
      fromBalance - t.amount < EPS
        ? `Clears ${fromName}'s balance`
        : `Settles €${t.amount.toFixed(2)} of ${fromName}'s €${fromBalance.toFixed(2)}`

    // "To" side: creditor receives some or all of what they are owed.
    // In Map balances, a creditor's amount is negative. The magnitude owed
    // is -toBalance.
    const owedBefore = -toBalance
    const owedAfter = owedBefore - t.amount
    const toPhrase =
      owedAfter < EPS
        ? `${toName} now even`
        : `${toName} still owed €${owedAfter.toFixed(2)}`

    result.push({
      fromUserId: t.fromUserId,
      toUserId: t.toUserId,
      amount: t.amount,
      annotation: `${fromPhrase} · ${toPhrase}`,
    })

    // Advance running balances for the next iteration.
    if (t.fromUserId) {
      running.set(
        t.fromUserId,
        Math.round((fromBalance - t.amount) * 100) / 100
      )
    }
    if (t.toUserId) {
      running.set(t.toUserId, Math.round((toBalance + t.amount) * 100) / 100)
    }
  }

  return result
}
```

- [ ] **Step 4: Run and confirm all pass**

Run:

```
cd frontend && pnpm exec vitest run src/utils/settlement.spec.ts
```

Expected: all existing tests + 7 new `annotateTransfers` tests pass.

- [ ] **Step 5: Commit**

```
git add frontend/src/utils/settlement.ts frontend/src/utils/settlement.spec.ts
git commit -m "Annotate each settlement transfer with plain-English derivation

Writes 'Clears Bob's balance · Dave now even' style subtext for each
transfer, driven off a simulated running balance so later annotations
reflect earlier transfers' effects. Used by the upcoming 'Show math'
expander."
```

---

### Task 3: Create `SettlementMath.vue` presentational component

**Files:**

- Create: `frontend/src/components/expenses/SettlementMath.vue`
- Create: `frontend/src/components/expenses/SettlementMath.spec.ts`

- [ ] **Step 1: Write the component test suite**

Create `frontend/src/components/expenses/SettlementMath.spec.ts`:

```typescript
import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import SettlementMath from './SettlementMath.vue'
import type { AnnotatedTransfer } from '@/utils/settlement'

function mount_(props: {
  balances: Map<string, number>
  transfers: AnnotatedTransfer[]
  nameFor: (userId: string) => string
  roundingDrift?: number
}) {
  return mount(SettlementMath, { props })
}

describe('SettlementMath', () => {
  const nameFor = (uid: string) =>
    ({ alice: 'Alice', bob: 'Bob', carol: 'Carol', dave: 'Dave' })[uid] ??
    'Unknown'

  const sampleTransfers: AnnotatedTransfer[] = [
    {
      fromUserId: 'bob',
      toUserId: 'dave',
      amount: 40,
      annotation: "Clears Bob's balance · Dave now even",
    },
    {
      fromUserId: 'carol',
      toUserId: 'alice',
      amount: 30,
      annotation: "Clears Carol's balance · Alice now even",
    },
  ]

  const sampleBalances = new Map<string, number>([
    ['alice', -30],
    ['bob', 40],
    ['carol', 30],
    ['dave', -40],
  ])

  it('renders one balance row per user with a non-zero balance', () => {
    const wrapper = mount_({
      balances: sampleBalances,
      transfers: sampleTransfers,
      nameFor,
    })
    const rows = wrapper.findAll('[data-testid="math-balance-row"]')
    expect(rows).toHaveLength(4)
  })

  it('orders creditors first (descending), then debtors (descending)', () => {
    const wrapper = mount_({
      balances: sampleBalances,
      transfers: sampleTransfers,
      nameFor,
    })
    const names = wrapper
      .findAll('[data-testid="math-balance-row"]')
      .map((r) => r.text())
    // Dave owed €40, Alice owed €30, Bob owes €40, Carol owes €30
    expect(names[0]).toContain('Dave')
    expect(names[0]).toContain('is owed €40.00')
    expect(names[1]).toContain('Alice')
    expect(names[1]).toContain('is owed €30.00')
    expect(names[2]).toContain('Bob')
    expect(names[2]).toContain('owes €40.00')
    expect(names[3]).toContain('Carol')
    expect(names[3]).toContain('owes €30.00')
  })

  it('renders each transfer with its annotation subtext', () => {
    const wrapper = mount_({
      balances: sampleBalances,
      transfers: sampleTransfers,
      nameFor,
    })
    const annotations = wrapper.findAll(
      '[data-testid="math-transfer-annotation"]'
    )
    expect(annotations).toHaveLength(2)
    expect(annotations[0]!.text()).toBe("Clears Bob's balance · Dave now even")
    expect(annotations[1]!.text()).toBe(
      "Clears Carol's balance · Alice now even"
    )
  })

  it('shows the rounding-drift warning when drift exceeds €0.01', () => {
    const wrapper = mount_({
      balances: sampleBalances,
      transfers: sampleTransfers,
      nameFor,
      roundingDrift: 0.05,
    })
    const drift = wrapper.find('[data-testid="math-drift"]')
    expect(drift.exists()).toBe(true)
    expect(drift.text()).toContain('€0.05')
  })

  it('hides the rounding-drift row when drift is 0 or undefined', () => {
    const wrapper = mount_({
      balances: sampleBalances,
      transfers: sampleTransfers,
      nameFor,
    })
    expect(wrapper.find('[data-testid="math-drift"]').exists()).toBe(false)
  })

  it('skips users whose rounded balance is below €0.01', () => {
    const wrapper = mount_({
      balances: new Map([
        ['alice', -0.001],
        ['bob', 0.001],
      ]),
      transfers: [],
      nameFor,
    })
    expect(wrapper.findAll('[data-testid="math-balance-row"]')).toHaveLength(0)
  })
})
```

- [ ] **Step 2: Run and confirm failure**

Run:

```
cd frontend && pnpm exec vitest run src/components/expenses/SettlementMath.spec.ts
```

Expected: error — module not found.

- [ ] **Step 3: Implement the component**

Create `frontend/src/components/expenses/SettlementMath.vue`:

```vue
<script setup lang="ts">
import { computed } from 'vue'
import type { AnnotatedTransfer } from '@/utils/settlement'
import { formatAmount } from '@/utils/format'

const props = defineProps<{
  balances: Map<string, number>
  transfers: AnnotatedTransfer[]
  nameFor: (userId: string) => string
  roundingDrift?: number
}>()

interface BalanceRow {
  userId: string
  name: string
  amount: number
}

const sortedBalances = computed((): BalanceRow[] => {
  const rows: BalanceRow[] = []
  for (const [userId, amount] of props.balances) {
    if (Math.abs(amount) < 0.005) continue
    rows.push({ userId, name: props.nameFor(userId), amount })
  }
  // Creditors first (most negative = most owed), then debtors (most positive)
  return rows.sort((a, b) => a.amount - b.amount)
})

const showDrift = computed(
  () => props.roundingDrift != null && Math.abs(props.roundingDrift) > 0.01
)
</script>

<template>
  <div
    class="rounded-md border border-gray-200 bg-gray-50 p-3 dark:border-stone-700 dark:bg-stone-800/50"
  >
    <p
      class="mb-2 text-xs font-medium tracking-wide text-gray-500 uppercase dark:text-stone-400"
    >
      Net balances
    </p>
    <div class="mb-3 space-y-1">
      <div
        v-for="row in sortedBalances"
        :key="row.userId"
        data-testid="math-balance-row"
        class="flex items-center justify-between text-sm"
      >
        <span class="truncate text-gray-800 dark:text-stone-200">
          {{ row.name }}
        </span>
        <span
          class="font-mono"
          :class="
            row.amount < 0
              ? 'text-green-700 dark:text-green-400'
              : 'text-red-700 dark:text-red-400'
          "
        >
          <template v-if="row.amount < 0">
            is owed {{ formatAmount(-row.amount) }}
          </template>
          <template v-else> owes {{ formatAmount(row.amount) }} </template>
        </span>
      </div>
      <div
        v-if="showDrift"
        data-testid="math-drift"
        class="mt-1 text-xs text-amber-700 dark:text-amber-400"
      >
        ⚠ Rounding drift {{ formatAmount(Math.abs(roundingDrift ?? 0)) }}
      </div>
    </div>

    <p
      class="mb-1 text-xs font-medium tracking-wide text-gray-500 uppercase dark:text-stone-400"
    >
      Transfers
    </p>
    <ul class="space-y-1">
      <li v-for="(t, i) in transfers" :key="i" class="text-sm">
        <div class="flex items-center justify-between">
          <span class="truncate text-gray-800 dark:text-stone-200">
            {{ t.fromUserId ? nameFor(t.fromUserId) : 'Unknown' }}
            <span class="text-gray-400 dark:text-stone-500"> → </span>
            {{ t.toUserId ? nameFor(t.toUserId) : 'Unknown' }}
          </span>
          <span class="font-mono text-gray-900 dark:text-white">
            {{ formatAmount(t.amount) }}
          </span>
        </div>
        <div
          data-testid="math-transfer-annotation"
          class="mt-0.5 text-xs text-gray-500 dark:text-stone-400"
        >
          {{ t.annotation }}
        </div>
      </li>
    </ul>
  </div>
</template>
```

- [ ] **Step 4: Run and confirm all pass**

Run:

```
cd frontend && pnpm exec vitest run src/components/expenses/SettlementMath.spec.ts
```

Expected: all 6 tests pass.

- [ ] **Step 5: Commit**

```
git add frontend/src/components/expenses/SettlementMath.vue frontend/src/components/expenses/SettlementMath.spec.ts
git commit -m "Add SettlementMath component for balances + annotated transfers"
```

---

### Task 4: Wire expander into the Settlement Preview modal

**Files:**

- Modify: `frontend/src/components/expenses/SettlementSection.vue`

This and Task 5 share one component change; we do them separately so commits stay focused. Task 4 adds an expander in the preview modal only. Task 5 adds it to each locked settlement card.

- [ ] **Step 1: Open the file and locate the preview-modal block**

The preview modal starts at the `<BaseModal … title="Settlement Preview">` element. Above the transfer list, after the amber "preview" banner and the "{unsettledExpenseCount} expense…" paragraph, we'll insert the expander.

- [ ] **Step 2: Import the new component, util, and name resolver**

In the `<script setup>` block of `SettlementSection.vue`, add to the existing imports:

```typescript
import SettlementMath from '@/components/expenses/SettlementMath.vue'
import {
  computeBalances,
  minimizeTransfers,
  annotateTransfers,
  type AnnotatedTransfer,
} from '@/utils/settlement'
```

Replace the existing `import { computeBalances, minimizeTransfers, type PreviewTransfer } from '@/utils/settlement'` — we now need `annotateTransfers` and `AnnotatedTransfer` too. Keep `PreviewTransfer` only if it is still referenced; if not, drop it.

Check whether `getMemberName` is already imported (it is — line 22 of the current file). It will serve as the name resolver.

- [ ] **Step 3: Add state and computed values for the preview expander**

In the `<script setup>` block, next to the other `ref`s:

```typescript
const previewMathOpen = ref(false)

const previewBalances = computed((): Map<string, number> => {
  if (!props.event.startDate || !props.event.endDate) return new Map()
  const unsettledExpenses = pool
    .getAll('expense')
    .filter((e) => e.eventId === props.event.id && !e.settlementId)
  const attendingRsvps = pool
    .getAll('rsvp')
    .filter((r) => r.eventId === props.event.id && r.attending)
  if (unsettledExpenses.length === 0 || attendingRsvps.length === 0) {
    return new Map()
  }
  const resolveParticipant = (pid: string) => {
    const p = pool.get('expenseParticipant', pid)
    return p ? { userId: p.userId, factor: p.factor } : undefined
  }
  return computeBalances(
    unsettledExpenses,
    attendingRsvps,
    props.event.startDate,
    props.event.endDate,
    resolveParticipant
  )
})

const previewAnnotatedTransfers = computed((): AnnotatedTransfer[] => {
  return annotateTransfers(
    previewTransfers.value,
    previewBalances.value,
    (userId) => getMemberName(userId, pool)
  )
})
```

Note: the existing `previewTransfers` computed already calls `computeBalances` and `minimizeTransfers`. To avoid double computation, refactor it to reuse `previewBalances`:

```typescript
const previewTransfers = computed((): PreviewTransfer[] => {
  return minimizeTransfers(previewBalances.value)
})
```

Keep the existing `PreviewTransfer` import if Vue/TS still needs it.

- [ ] **Step 4: Render the expander in the preview modal template**

Inside the `<BaseModal … title="Settlement Preview">` block, after the `<p class="mb-3 …">{{ unsettledExpenseCount }} expense…</p>` and before the `<div v-if="previewTransfers.length > 0" …>`, insert:

```vue
<div v-if="previewTransfers.length > 0" class="mb-3">
  <button
    type="button"
    class="flex w-full items-center justify-between rounded-md px-2 py-1 text-sm text-gray-600 hover:bg-gray-100 dark:text-stone-400 dark:hover:bg-stone-700/50"
    data-testid="preview-math-toggle"
    @click="previewMathOpen = !previewMathOpen"
  >
    <span>{{ previewMathOpen ? 'Hide math' : 'Show math' }}</span>
    <ChevronDownIcon
      class="size-4 transition-transform"
      :class="{ 'rotate-180': previewMathOpen }"
    />
  </button>
  <div v-if="previewMathOpen" class="mt-2">
    <SettlementMath
      :balances="previewBalances"
      :transfers="previewAnnotatedTransfers"
      :name-for="(uid) => getMemberName(uid, pool)"
    />
  </div>
</div>
```

Add `ChevronDownIcon` to the heroicons import at the top of the script block:

```typescript
import {
  BanknotesIcon,
  CalculatorIcon,
  CheckCircleIcon,
  ChevronDownIcon, // add this
  // …rest unchanged
} from '@heroicons/vue/24/outline'
```

- [ ] **Step 5: Manually verify in dev server**

Run:

```
mise run dev
```

Navigate to an event expenses page with at least 2 users and some expenses, click **Start settlement**, then click **Show math**. Confirm:

- Balances panel appears with creditors above debtors.
- Each transfer has a subtext line like "Clears Bob's balance · Dave now even".
- Clicking **Hide math** collapses it.

Stop the dev server.

- [ ] **Step 6: Run typecheck + existing tests**

Run in parallel:

```
cd frontend && pnpm exec vue-tsc --noEmit
cd frontend && pnpm exec vitest run src/components/expenses src/utils/settlement.spec.ts
```

Expected: no type errors; all existing and new tests pass.

- [ ] **Step 7: Commit**

```
git add frontend/src/components/expenses/SettlementSection.vue
git commit -m "Reveal settlement math in the preview modal

Adds a collapsed 'Show math' toggle above the transfer list that expands
to show net balances and per-transfer annotations, so users can verify
the proposed transfers before confirming."
```

---

### Task 5: Wire expander into each locked settlement card

**Files:**

- Modify: `frontend/src/components/expenses/SettlementSection.vue`

- [ ] **Step 1: Add state for per-card open/closed tracking**

In the `<script setup>` block, below `previewMathOpen`:

```typescript
const openMathSettlementIds = ref(new Set<string>())

function toggleSettlementMath(id: string) {
  const next = new Set(openMathSettlementIds.value)
  if (next.has(id)) next.delete(id)
  else next.add(id)
  openMathSettlementIds.value = next
}

function isSettlementMathOpen(id: string): boolean {
  return openMathSettlementIds.value.has(id)
}
```

- [ ] **Step 2: Add helpers that build balances + annotated transfers for a locked settlement**

Continuing in `<script setup>`:

```typescript
function balancesForSettlement(settlementId: string): Map<string, number> {
  return deriveBalancesFromTransfers(transfersForSettlement(settlementId))
}

function annotatedTransfersForSettlement(
  settlementId: string
): AnnotatedTransfer[] {
  return annotateTransfers(
    transfersForSettlement(settlementId),
    balancesForSettlement(settlementId),
    (uid) => getMemberName(uid, pool)
  )
}
```

Add `deriveBalancesFromTransfers` to the existing `@/utils/settlement` import.

- [ ] **Step 3: Add the toggle + panel inside the settlement-card header**

In the template, inside the settlement card's header row (the `<div class="flex flex-wrap items-center justify-between … bg-gray-50 …">` that currently holds "Settled by X on …" and the delete button), the header needs a new row below it that toggles the math panel. The cleanest placement: a second header row directly under the existing header, before the `<div class="divide-y …">` block that lists transfers.

Between the current header `<div>…</div>` and the transfers `<div class="divide-y divide-gray-100 …">`, insert:

```vue
<div
  v-if="transfersForSettlement(settlement.id).length > 0"
  class="border-b border-gray-100 px-3 py-1.5 dark:border-stone-700/50"
>
  <button
    type="button"
    class="flex w-full items-center justify-between rounded-md px-1.5 py-1 text-xs text-gray-600 hover:bg-gray-100 dark:text-stone-400 dark:hover:bg-stone-700/50"
    :data-testid="`settlement-math-toggle-${settlement.id}`"
    @click="toggleSettlementMath(settlement.id)"
  >
    <span>
      {{ isSettlementMathOpen(settlement.id) ? 'Hide math' : 'Show math' }}
    </span>
    <ChevronDownIcon
      class="size-4 transition-transform"
      :class="{ 'rotate-180': isSettlementMathOpen(settlement.id) }"
    />
  </button>
  <div v-if="isSettlementMathOpen(settlement.id)" class="mt-2">
    <SettlementMath
      :balances="balancesForSettlement(settlement.id)"
      :transfers="annotatedTransfersForSettlement(settlement.id)"
      :name-for="(uid) => getMemberName(uid, pool)"
    />
  </div>
</div>
```

- [ ] **Step 4: Run the frontend suite to confirm no regressions**

Run:

```
cd frontend && pnpm exec vitest run src/components/expenses src/utils/settlement.spec.ts
cd frontend && pnpm exec vue-tsc --noEmit
```

Expected: all green.

- [ ] **Step 5: Manually verify**

Run `mise run dev`. Visit an expenses page where at least one settlement has been created. Confirm:

- "Show math" toggle appears beneath the gray header on the settlement card.
- Expanding reveals the same style of balances + annotated transfers as the preview.
- Collapsing works.
- Multiple settlements can be expanded independently.

- [ ] **Step 6: Commit**

```
git add frontend/src/components/expenses/SettlementSection.vue
git commit -m "Reveal settlement math on locked settlement cards

Derives balances from each settlement's stored transfers so the audit
view is self-consistent regardless of later RSVP changes. Each card
tracks its own open/closed state so several settlements can be expanded
side by side."
```

---

### Task 6: E2E test for preview + locked expander

**Files:**

- Modify: `e2e/tests/settlements.spec.ts`

- [ ] **Step 1: Add a new test inside the existing `Settlements UI` describe (file has this describe around line 205)**

Add this test after the existing `delete settlement removes it from the page` test, still inside the `Settlements UI` describe so it inherits the `sessionToken` / `apiContext` `beforeAll` setup:

```typescript
test('show math expander reveals balances and annotations pre and post settlement', async ({
  page,
  playwright,
}) => {
  const { eventId } = await createResolvedEvent(apiContext, 'Math Expander UI')

  // Add a second attending user so the split has two parties and produces
  // at least one transfer. (Pattern mirrored from 'Mixed Expense Settlement'.)
  const workspaceId = await getWorkspaceId(apiContext)
  const bobContext = await newApiContext(playwright)
  const bobEmail = `e2e-math-bob-${Date.now()}@example.com`
  await getTestSession(bobContext, bobEmail, 'Math Bob')
  await addMemberToWorkspace(apiContext, workspaceId, bobEmail)
  await bobContext.post(`${API_BASE}/api/events/${eventId}/rsvps`, {
    data: {
      attending: true,
      start_date: DEFAULT_START,
      end_date: DEFAULT_END,
    },
  })

  // Alice pays €50 groceries for the whole trip → Bob will owe €25.
  await apiContext.post(`${API_BASE}/api/expenses`, {
    data: {
      event_id: eventId,
      description: 'Groceries',
      amount: 50,
      start_date: DEFAULT_START,
      end_date: DEFAULT_END,
    },
  })

  await setupAuthenticatedPage(page, sessionToken)
  await page.goto(`/events/${eventId}/expenses`)

  await expect(page.getByRole('heading', { name: 'Settlements' })).toBeVisible({
    timeout: PAGE_LOAD_TIMEOUT,
  })

  // Open preview, expand math.
  await page.getByTestId('start-settlement-button').click()
  await expect(page.getByText('This is a preview')).toBeVisible()
  await page.getByTestId('preview-math-toggle').click()
  await expect(page.getByText('Net balances')).toBeVisible()
  await expect(
    page.locator('[data-testid="math-transfer-annotation"]').first()
  ).toContainText(/Clears .+'s balance|Settles €/)

  // Confirm settlement.
  await page.getByRole('button', { name: /Confirm/ }).click()
  await expect(page.getByText(/Settled by/)).toBeVisible()

  // Expand the locked-card math; same derivation style.
  const lockedToggle = page
    .locator('[data-testid^="settlement-math-toggle-"]')
    .first()
  await lockedToggle.click()
  await expect(page.getByText('Net balances')).toBeVisible()
  await expect(
    page.locator('[data-testid="math-transfer-annotation"]').first()
  ).toContainText(/Clears .+'s balance|Settles €/)

  await bobContext.dispose()
})
```

- [ ] **Step 2: Run the full E2E suite**

Run:

```
mise run e2e -- --grep "show math expander"
```

Expected: the new test passes. If multi-user setup needs adjustment, follow the exact helper calls used in the adjacent `Mixed Expense Settlement > settles mixed expense types correctly …` test (same file).

- [ ] **Step 3: Run the full `mise run check` to catch any lint/type regressions**

Run:

```
mise run check
```

Expected: all green.

- [ ] **Step 4: Commit**

```
git add e2e/tests/settlements.spec.ts
git commit -m "E2E: verify Show math expander on preview and locked cards

Asserts the balances panel and annotation subtext render both before
confirming a settlement and after it is locked, proving the derived-
from-transfers path matches the live-computed path."
```

---

## Closing checks

- [ ] `mise run check` passes (lint + typecheck + unit tests + audit).
- [ ] `mise run e2e` passes.
- [ ] Manually exercised preview + locked expanders in dev.
- [ ] Spec goals covered:
  - Expander on preview modal ✓ Task 4
  - Expander on locked settlement cards ✓ Task 5
  - Net balances panel ✓ Task 3 / component
  - Per-transfer annotations ✓ Task 2 + Task 3
  - Data source: `computeBalances` for preview, derived from transfers for locked ✓ Tasks 4, 5
  - Zero-transfer case: expander does not render ✓ Task 4, Task 5 (gated on `previewTransfers.length > 0` / `transfersForSettlement(id).length > 0`)
  - Rounding drift warning ✓ Task 3 component (prop currently unused — see below)
- [ ] No backend changes, no migration.

### Known follow-ups (explicitly out of scope for this plan)

- `roundingDrift` is implemented on the component but not wired from callers. If drift detection becomes valuable in practice, compute it in `SettlementSection.vue` as `sum(balances.values())` and pass it in. Left dangling here because `computeBalances` and `deriveBalancesFromTransfers` already round to €0.01 per entry, so drift above €0.01 shouldn't arise naturally and adding the check everywhere is noise without a signal.
- Per-person drilldown (click a name → see each expense contributing to their share) is a separate feature tracked elsewhere.
