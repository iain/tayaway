<script setup lang="ts">
import { computed } from 'vue'
import type { AnnotatedTransfer } from '@/utils/settlement'
import LedgerAmount from '@/components/common/LedgerAmount.vue'

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
  const creditors: BalanceRow[] = []
  const debtors: BalanceRow[] = []
  for (const [userId, amount] of props.balances) {
    if (Math.abs(amount) < 0.005) continue
    const row = { userId, name: props.nameFor(userId), amount }
    if (amount < 0) creditors.push(row)
    else debtors.push(row)
  }
  // Creditors first, largest-owed first (most negative first).
  creditors.sort((a, b) => a.amount - b.amount)
  // Then debtors, largest-debt first.
  debtors.sort((a, b) => b.amount - a.amount)
  return [...creditors, ...debtors]
})

const showDrift = computed(
  () => props.roundingDrift != null && Math.abs(props.roundingDrift) > 0.01
)
</script>

<template>
  <div class="border-line bg-surface-sunken rounded-md border p-3">
    <p class="text-ink-muted mb-2 text-xs font-medium tracking-wide uppercase">
      Net balances
    </p>
    <div class="mb-3 space-y-1">
      <div
        v-for="row in sortedBalances"
        :key="row.userId"
        data-testid="math-balance-row"
        class="flex items-center justify-between text-sm"
      >
        <span class="text-ink truncate">
          {{ row.name }}
        </span>
        <span>
          <template v-if="row.amount < 0">
            is owed <LedgerAmount :amount="-row.amount" />
          </template>
          <template v-else>
            owes <LedgerAmount :amount="row.amount" />
          </template>
        </span>
      </div>
      <div
        v-if="showDrift"
        data-testid="math-drift"
        class="mt-1 text-xs text-amber-700 dark:text-amber-400"
      >
        ⚠ Rounding drift <LedgerAmount :amount="Math.abs(roundingDrift ?? 0)" />
      </div>
    </div>

    <p class="text-ink-muted mb-1 text-xs font-medium tracking-wide uppercase">
      Transfers
    </p>
    <ul class="space-y-1">
      <li v-for="(t, i) in transfers" :key="i" class="text-sm">
        <div class="flex items-center justify-between">
          <span class="text-ink truncate">
            {{ t.fromUserId ? nameFor(t.fromUserId) : 'Unknown' }}
            <span class="text-ink-muted"> → </span>
            {{ t.toUserId ? nameFor(t.toUserId) : 'Unknown' }}
          </span>
          <span class="text-ink">
            <LedgerAmount :amount="t.amount" />
          </span>
        </div>
        <div
          data-testid="math-transfer-annotation"
          class="text-ink-muted mt-0.5 text-xs"
        >
          {{ t.annotation }}
        </div>
      </li>
    </ul>
  </div>
</template>
