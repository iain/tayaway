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
