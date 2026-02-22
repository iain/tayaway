<script setup lang="ts">
import { computed } from 'vue'
import { TrashIcon } from '@heroicons/vue/24/outline'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useExpensesStore } from '@/stores/expenses'
import type { PoolExpense } from '@/types/pool'

const props = defineProps<{
  expense: PoolExpense
  currentMemberId: string | null
}>()

const pool = useObjectPoolStore()
const expensesStore = useExpensesStore()

const member = computed(() => {
  if (!props.expense.memberId) return null
  return pool.get('member', props.expense.memberId)
})

const displayName = computed(() => {
  return member.value?.name || member.value?.email || 'Unknown'
})

const formattedAmount = computed(() => {
  return `€${props.expense.amount.toFixed(2)}`
})

const isOwner = computed(() => {
  return props.expense.memberId === props.currentMemberId
})

async function handleDelete() {
  await expensesStore.deleteExpense(props.expense.id)
}
</script>

<template>
  <div
    data-testid="expense-row"
    class="flex items-center justify-between gap-4 py-3"
  >
    <div class="min-w-0 flex-1">
      <p class="truncate text-sm text-gray-900 dark:text-white">
        {{ expense.description }}
      </p>
      <p class="text-xs text-gray-500 dark:text-stone-400">
        {{ displayName }}
      </p>
    </div>
    <div class="flex items-center gap-3">
      <span class="font-mono text-sm font-medium text-gray-900 dark:text-white">
        {{ formattedAmount }}
      </span>
      <button
        v-if="isOwner"
        type="button"
        class="text-gray-400 hover:text-red-500 dark:text-stone-500 dark:hover:text-red-400"
        @click="handleDelete"
      >
        <TrashIcon class="size-4" />
      </button>
    </div>
  </div>
</template>
