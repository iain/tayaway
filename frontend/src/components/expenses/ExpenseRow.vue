<script setup lang="ts">
import { computed } from 'vue'
import { TrashIcon } from '@heroicons/vue/24/outline'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useExpensesStore } from '@/stores/expenses'
import type { PoolExpense } from '@/types/pool'

const props = defineProps<{
  expense: PoolExpense
  currentUserId: string | null
  stripe?: boolean
}>()

const pool = useObjectPoolStore()
const expensesStore = useExpensesStore()

const member = computed(() => {
  if (!props.expense.userId) return null
  return pool.findBy('member', 'userId', props.expense.userId)
})

const displayName = computed(() => {
  return member.value?.name || member.value?.email || 'Unknown'
})

const formattedAmount = computed(() => {
  return `€${props.expense.amount.toFixed(2)}`
})

const isOwner = computed(() => {
  return props.expense.userId === props.currentUserId
})

async function handleDelete() {
  await expensesStore.deleteExpense(props.expense.id)
}
</script>

<template>
  <tr
    data-testid="expense-row"
    :class="stripe ? 'bg-gray-50 dark:bg-black/20' : ''"
  >
    <td class="py-3 pr-4 pl-2 align-middle">
      <p class="truncate text-sm text-gray-900 dark:text-white">
        {{ expense.description }}
      </p>
      <p class="text-xs text-gray-500 dark:text-stone-400">
        {{ displayName }}
      </p>
    </td>
    <td
      class="py-3 pr-4 text-right align-middle font-mono text-sm font-medium whitespace-nowrap text-gray-900 dark:text-white"
    >
      {{ formattedAmount }}
    </td>
    <td class="w-8 py-3 pr-2 align-middle">
      <button
        v-if="isOwner"
        type="button"
        class="flex text-gray-400 hover:text-red-500 dark:text-stone-500 dark:hover:text-red-400"
        @click="handleDelete"
      >
        <TrashIcon class="size-4" />
      </button>
    </td>
  </tr>
</template>
