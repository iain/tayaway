<script setup lang="ts">
import { computed, onMounted } from 'vue'
import { storeToRefs } from 'pinia'
import { useRoute, useRouter } from 'vue-router'
import { ArrowLeftIcon } from '@heroicons/vue/24/outline'
import { useAuthStore } from '@/stores'
import { useObjectPoolStore } from '@/stores/objectPool'
import { api } from '@/api/client'
import TextButton from '@/components/common/TextButton.vue'
import ExpenseRow from '@/components/expenses/ExpenseRow.vue'
import AddExpenseForm from '@/components/expenses/AddExpenseForm.vue'
import type { PoolApiResponse } from '@/types/pool'

const route = useRoute()
const router = useRouter()
const authStore = useAuthStore()
const pool = useObjectPoolStore()
const { currentMemberId } = storeToRefs(authStore)

const eventId = computed(() => route.params.id as string)

const event = computed(() => pool.get('event', eventId.value))

const expenses = computed(() =>
  pool
    .getAll('expense')
    .filter((e) => e.eventId === eventId.value)
    .sort((a, b) => a.createdAt.localeCompare(b.createdAt))
)

const total = computed(() =>
  expenses.value.reduce((sum, e) => sum + e.amount, 0)
)

const formattedTotal = computed(() => `€${total.value.toFixed(2)}`)

onMounted(async () => {
  await api.get<PoolApiResponse>(`/expenses?event_id=${eventId.value}`)
})

function handleBack(): void {
  router.push(`/events/${eventId.value}`)
}
</script>

<template>
  <div>
    <div class="mb-6">
      <TextButton @click="handleBack">
        <ArrowLeftIcon class="size-4" />
        Back to Event
      </TextButton>
    </div>

    <div v-if="!event" class="text-gray-500 dark:text-stone-400">
      Event not found
    </div>

    <div v-else>
      <div class="mb-6 flex items-baseline justify-between">
        <h1
          class="text-2xl font-bold tracking-tight text-gray-900 dark:text-white"
        >
          Expenses
        </h1>
        <span class="text-lg font-semibold text-gray-700 dark:text-stone-300">
          {{ formattedTotal }} total
        </span>
      </div>

      <div
        v-if="expenses.length > 0"
        class="mb-6 divide-y divide-gray-100 dark:divide-stone-700"
      >
        <ExpenseRow
          v-for="expense in expenses"
          :key="expense.id"
          :expense="expense"
          :current-member-id="currentMemberId"
        />
      </div>

      <p v-else class="mb-6 text-sm text-gray-500 dark:text-stone-400">
        No expenses recorded yet.
      </p>

      <AddExpenseForm :event-id="eventId" />
    </div>
  </div>
</template>
