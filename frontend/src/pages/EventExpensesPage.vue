<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { storeToRefs } from 'pinia'
import { useRoute } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useObjectPoolStore } from '@/stores/objectPool'
import { api } from '@/api/client'
import ExpenseRow from '@/components/expenses/ExpenseRow.vue'
import AddExpenseModal from '@/components/expenses/AddExpenseModal.vue'
import ExpenseSplit from '@/components/expenses/ExpenseSplit.vue'
import SettlementSection from '@/components/expenses/SettlementSection.vue'
import PrimaryButton from '@/components/common/PrimaryButton.vue'
import type { PoolApiResponse, PoolExpense } from '@/types/pool'

const route = useRoute()
const authStore = useAuthStore()
const pool = useObjectPoolStore()
const { currentUserId } = storeToRefs(authStore)

const isModalOpen = ref(false)
const editingExpense = ref<PoolExpense | undefined>(undefined)

function openAdd() {
  editingExpense.value = undefined
  isModalOpen.value = true
}

function openEdit(expense: PoolExpense) {
  editingExpense.value = expense
  isModalOpen.value = true
}

function closeModal() {
  isModalOpen.value = false
  editingExpense.value = undefined
}

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
  await Promise.all([
    api.get<PoolApiResponse>(`/expenses?event_id=${eventId.value}`),
    api.get<PoolApiResponse>(`/events/${eventId.value}/rsvps`),
    api.get<PoolApiResponse>(`/settlements?event_id=${eventId.value}`),
  ])
})
</script>

<template>
  <div>
    <div v-if="!event" class="text-gray-500 dark:text-stone-400">
      Event not found
    </div>

    <div v-else>
      <div class="mb-6 flex items-center justify-between">
        <div class="flex items-baseline gap-4">
          <h1
            class="text-2xl font-bold tracking-tight text-gray-900 dark:text-white"
          >
            Expenses
          </h1>
          <span class="text-lg font-semibold text-gray-700 dark:text-stone-300">
            {{ formattedTotal }} total
          </span>
        </div>
        <PrimaryButton @click="openAdd">Add expense</PrimaryButton>
      </div>

      <div
        v-if="expenses.length > 0"
        class="mb-6 overflow-hidden rounded-lg border border-gray-200 dark:border-stone-700"
      >
        <table class="w-full text-sm">
          <tbody>
            <ExpenseRow
              v-for="(expense, i) in expenses"
              :key="expense.id"
              :expense="expense"
              :event="event"
              :current-user-id="currentUserId"
              :stripe="i % 2 === 0"
              @edit="openEdit"
            />
          </tbody>
        </table>
      </div>

      <p v-else class="mb-6 text-sm text-gray-500 dark:text-stone-400">
        No expenses recorded yet.
      </p>

      <AddExpenseModal
        :open="isModalOpen"
        :event="event"
        :expense="editingExpense"
        @close="closeModal"
      />

      <ExpenseSplit v-if="event" :event="event" :total="total" />

      <SettlementSection
        v-if="event"
        :event="event"
        :current-user-id="currentUserId"
      />
    </div>
  </div>
</template>
