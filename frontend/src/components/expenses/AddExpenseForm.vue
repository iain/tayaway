<script setup lang="ts">
import { ref } from 'vue'
import { useExpensesStore } from '@/stores/expenses'
import CurrencyInput from '@/components/form/CurrencyInput.vue'

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
    <div
      class="flex min-w-0 flex-1 items-center rounded-md bg-gray-100 px-3 outline-1 -outline-offset-1 outline-gray-300 focus-within:outline-2 focus-within:-outline-offset-2 focus-within:outline-cyan-500 dark:bg-white/5 dark:outline-white/10 dark:focus-within:outline-cyan-500"
    >
      <input
        v-model="description"
        type="text"
        placeholder="Description"
        class="block min-w-0 grow bg-transparent py-1.5 text-sm/6 text-gray-900 placeholder:text-gray-400 focus:outline-none dark:text-white dark:placeholder:text-stone-500"
      />
    </div>
    <CurrencyInput v-model="amount" class="w-28" placeholder="0.00" />
    <button
      type="submit"
      :disabled="submitting"
      class="rounded-md bg-cyan-600 px-3 py-1.5 text-sm/6 font-medium text-white hover:bg-cyan-700 disabled:opacity-50 dark:bg-cyan-700 dark:hover:bg-cyan-600"
    >
      Add
    </button>
  </form>
</template>
