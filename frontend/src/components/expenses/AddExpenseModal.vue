<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import BaseModal from '@/components/common/BaseModal.vue'
import FormInput from '@/components/form/FormInput.vue'
import FormActions from '@/components/form/FormActions.vue'
import { useExpensesStore } from '@/stores/expenses'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useAuthStore } from '@/stores/auth'
import type { PoolEvent } from '@/types/pool'

const props = defineProps<{
  open: boolean
  event: PoolEvent
}>()

const emit = defineEmits<{
  close: []
}>()

const expensesStore = useExpensesStore()
const pool = useObjectPoolStore()
const authStore = useAuthStore()

const description = ref('')
const amount = ref('')
const startDate = ref('')
const endDate = ref('')
const submitting = ref(false)

const eventHasDates = computed(
  () => props.event.startDate != null && props.event.endDate != null
)

watch(
  () => props.open,
  (isOpen) => {
    if (isOpen) {
      description.value = ''
      amount.value = ''

      if (eventHasDates.value) {
        // Pre-fill from current user's RSVP dates if partial, otherwise event dates
        const userId = authStore.currentUserId
        const rsvp = userId
          ? pool
              .getAll('rsvp')
              .find(
                (r) =>
                  r.eventId === props.event.id &&
                  r.userId === userId &&
                  r.attending
              )
          : null

        if (rsvp?.startDate && rsvp?.endDate) {
          startDate.value = rsvp.startDate
          endDate.value = rsvp.endDate
        } else {
          startDate.value = props.event.startDate!
          endDate.value = props.event.endDate!
        }
      } else {
        const today = new Date().toISOString().slice(0, 10)
        startDate.value = today
        endDate.value = today
      }
    }
  }
)

async function handleSubmit(): Promise<void> {
  const desc = description.value.trim()
  const amt = parseFloat(amount.value)
  if (!desc || isNaN(amt) || amt <= 0) return
  if (!startDate.value || !endDate.value) return

  submitting.value = true
  try {
    await expensesStore.createExpense(
      props.event.id,
      desc,
      amt,
      startDate.value,
      endDate.value
    )
    emit('close')
  } finally {
    submitting.value = false
  }
}

function handleClose(): void {
  emit('close')
}
</script>

<template>
  <BaseModal :open="open" title="Add Expense" @close="handleClose">
    <form class="space-y-4" @submit.prevent="handleSubmit">
      <FormInput
        id="expense-description"
        v-model="description"
        label="Description"
        placeholder="What was this expense for?"
        autofocus
        :disabled="submitting"
      />

      <FormInput
        id="expense-amount"
        v-model="amount"
        label="Amount"
        placeholder="0.00"
        prefix="€"
        inputmode="decimal"
        :disabled="submitting"
      />

      <div v-if="eventHasDates">
        <label
          class="mb-1 block text-sm font-medium text-gray-700 dark:text-stone-300"
        >
          Dates
        </label>
        <div class="flex items-center gap-2">
          <input
            v-model="startDate"
            type="date"
            data-testid="expense-start-date"
            :min="event.startDate ?? undefined"
            :max="event.endDate ?? undefined"
            :disabled="submitting"
            class="rounded-md border border-gray-300 px-2 py-1 text-sm dark:border-stone-600 dark:bg-stone-700 dark:text-white"
          />
          <span class="text-gray-500 dark:text-stone-400">to</span>
          <input
            v-model="endDate"
            type="date"
            data-testid="expense-end-date"
            :min="event.startDate ?? undefined"
            :max="event.endDate ?? undefined"
            :disabled="submitting"
            class="rounded-md border border-gray-300 px-2 py-1 text-sm dark:border-stone-600 dark:bg-stone-700 dark:text-white"
          />
        </div>
      </div>

      <FormActions
        submit-label="Add Expense"
        loading-label="Adding..."
        :loading="submitting"
        :disabled="!description.trim() || !(parseFloat(amount) > 0)"
        @cancel="handleClose"
      />
    </form>
  </BaseModal>
</template>
