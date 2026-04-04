<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { storeToRefs } from 'pinia'
import { useRoute } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useObjectPoolStore } from '@/stores/objectPool'
import { api } from '@/api/client'
import ExpenseRow from '@/components/expenses/ExpenseRow.vue'
import AddExpenseModal from '@/components/expenses/AddExpenseModal.vue'
import ExpenseSplit from '@/components/expenses/ExpenseSplit.vue'
import SettlementSection from '@/components/expenses/SettlementSection.vue'
import BaseModal from '@/components/common/BaseModal.vue'
import AppButton from '@/components/common/AppButton.vue'
import TextButton from '@/components/common/TextButton.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import { CurrencyEuroIcon } from '@heroicons/vue/24/outline'
import { useExpenseActions } from '@/composables/useExpenseActions'
import type { PoolApiResponse, PoolExpense } from '@/types/pool'

const route = useRoute()
const { pendingAdd, resetAdd } = useExpenseActions()
const authStore = useAuthStore()
const pool = useObjectPoolStore()
const { currentUserId } = storeToRefs(authStore)

const isModalOpen = ref(false)
const editingExpense = ref<PoolExpense | undefined>(undefined)
const showRsvpDialog = ref(false)

watch(pendingAdd, (val) => {
  if (val) {
    resetAdd()
    openAdd()
  }
})

function openAdd() {
  if (!userIsAttending.value) {
    showRsvpDialog.value = true
    return
  }
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

const userIsAttending = computed(() => {
  if (!currentUserId.value) return false
  const rsvp = pool
    .getAll('rsvp')
    .find(
      (r) => r.eventId === eventId.value && r.userId === currentUserId.value
    )
  return rsvp?.attending === true
})

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
          <span
            data-testid="expenses-total"
            class="text-lg font-semibold text-gray-700 dark:text-stone-300"
          >
            {{ formattedTotal }} total
          </span>
        </div>
        <AppButton v-if="expenses.length > 0" @click="openAdd"
          >Add expense</AppButton
        >
      </div>

      <div v-if="expenses.length > 0" class="mb-6 space-y-3">
        <ExpenseRow
          v-for="expense in expenses"
          :key="expense.id"
          :expense="expense"
          :event="event"
          :current-user-id="currentUserId"
          @edit="openEdit"
        />
      </div>

      <EmptyState
        v-else
        :icon="CurrencyEuroIcon"
        heading="No expenses yet"
        description="Add your first expense to start tracking costs."
      >
        <AppButton @click="openAdd">Add expense</AppButton>
      </EmptyState>

      <AddExpenseModal
        :open="isModalOpen"
        :event="event"
        :expense="editingExpense"
        @close="closeModal"
      />

      <BaseModal
        :open="showRsvpDialog"
        title="RSVP required"
        size="sm"
        @close="showRsvpDialog = false"
      >
        <p
          data-testid="rsvp-required-dialog"
          class="text-sm text-gray-600 dark:text-stone-400"
        >
          You need to RSVP as attending before you can add expenses. This
          ensures costs are split among attendees only.
        </p>
        <div class="mt-6 flex justify-end gap-3">
          <TextButton variant="secondary" @click="showRsvpDialog = false">
            Cancel
          </TextButton>
          <AppButton
            :to="`/events/${eventId}/rsvp`"
            autofocus
            @click="showRsvpDialog = false"
          >
            Go to RSVP
          </AppButton>
        </div>
      </BaseModal>

      <ExpenseSplit
        v-if="event && expenses.length > 0"
        :event="event"
        :total="total"
      />

      <SettlementSection
        v-if="event && expenses.length > 0"
        :event="event"
        :current-user-id="currentUserId"
      />
    </div>
  </div>
</template>
