<script setup lang="ts">
import { ref } from 'vue'
import { useExpensesStore } from '@/stores/expenses'

const props = defineProps<{
  eventId: string
}>()

const expensesStore = useExpensesStore()

const description = ref('')
const amount = ref('')
const submitting = ref(false)

async function handleSubmit() {
  const desc = description.value.trim()
  const amt = parseFloat(amount.value)
  if (!desc || isNaN(amt) || amt <= 0) return

  submitting.value = true
  try {
    await expensesStore.createExpense(props.eventId, desc, amt)
    description.value = ''
    amount.value = ''
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <form class="flex gap-2" @submit.prevent="handleSubmit">
    <input
      v-model="description"
      type="text"
      placeholder="Description"
      class="min-w-0 flex-1 rounded-md border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 placeholder-gray-400 focus:border-cyan-500 focus:ring-1 focus:ring-cyan-500 focus:outline-none dark:border-stone-600 dark:bg-stone-800 dark:text-white dark:placeholder-stone-500 dark:focus:border-cyan-500"
    />
    <input
      v-model="amount"
      type="number"
      step="0.01"
      min="0.01"
      placeholder="€0.00"
      class="w-28 rounded-md border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 placeholder-gray-400 focus:border-cyan-500 focus:ring-1 focus:ring-cyan-500 focus:outline-none dark:border-stone-600 dark:bg-stone-800 dark:text-white dark:placeholder-stone-500 dark:focus:border-cyan-500"
    />
    <button
      type="submit"
      :disabled="submitting"
      class="rounded-md bg-cyan-600 px-3 py-2 text-sm font-medium text-white hover:bg-cyan-700 disabled:opacity-50 dark:bg-cyan-700 dark:hover:bg-cyan-600"
    >
      Add
    </button>
  </form>
</template>
