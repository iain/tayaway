<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { ChevronLeftIcon, ChevronRightIcon } from '@heroicons/vue/24/outline'
import BaseModal from '@/components/common/BaseModal.vue'
import IconButton from '@/components/common/IconButton.vue'
import FormInput from '@/components/form/FormInput.vue'
import FormActions from '@/components/form/FormActions.vue'
import CalendarMonth from '@/components/calendar/CalendarMonth.vue'
import { useExpensesStore } from '@/stores/expenses'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useAuthStore } from '@/stores/auth'
import { useCalendar, getMonthName } from '@/composables/useCalendar'
import type { PoolEvent, PoolExpense } from '@/types/pool'

const props = defineProps<{
  open: boolean
  event: PoolEvent
  expense?: PoolExpense
}>()

const emit = defineEmits<{
  close: []
}>()

const expensesStore = useExpensesStore()
const pool = useObjectPoolStore()
const authStore = useAuthStore()
const { formatDateDisplay } = useCalendar()

const description = ref('')
const amount = ref('')
const startDate = ref('')
const endDate = ref('')
const submitting = ref(false)

// Calendar navigation state
const calendarYear = ref(new Date().getFullYear())
const calendarMonth = ref(new Date().getMonth())
const hoverDate = ref<string | null>(null)

const isEditing = computed(() => props.expense != null)

const modalTitle = computed(() =>
  isEditing.value ? 'Edit Expense' : 'Add Expense'
)

const eventHasDates = computed(
  () => props.event.startDate != null && props.event.endDate != null
)

const selectionText = computed(() => {
  if (startDate.value && endDate.value) {
    if (startDate.value === endDate.value) {
      return formatDateDisplay(startDate.value)
    }
    return `${formatDateDisplay(startDate.value)} – ${formatDateDisplay(endDate.value)}`
  }
  if (startDate.value) {
    return `${formatDateDisplay(startDate.value)} – Select end date`
  }
  return 'Select start date'
})

const monthLabel = computed(
  () => `${getMonthName(calendarMonth.value)} ${calendarYear.value}`
)

// Constrain navigation to months that overlap with the event range
const canNavigatePrev = computed(() => {
  if (!props.event.startDate) return true
  const [minYear, minMonth] = props.event.startDate.split('-').map(Number) as [
    number,
    number,
  ]
  // Can go back if current month is after the event start month
  return (
    calendarYear.value > minYear ||
    (calendarYear.value === minYear && calendarMonth.value > minMonth - 1)
  )
})

const canNavigateNext = computed(() => {
  if (!props.event.endDate) return true
  const [maxYear, maxMonth] = props.event.endDate.split('-').map(Number) as [
    number,
    number,
  ]
  return (
    calendarYear.value < maxYear ||
    (calendarYear.value === maxYear && calendarMonth.value < maxMonth - 1)
  )
})

function navigatePrev(): void {
  if (!canNavigatePrev.value) return
  if (calendarMonth.value === 0) {
    calendarMonth.value = 11
    calendarYear.value--
  } else {
    calendarMonth.value--
  }
}

function navigateNext(): void {
  if (!canNavigateNext.value) return
  if (calendarMonth.value === 11) {
    calendarMonth.value = 0
    calendarYear.value++
  } else {
    calendarMonth.value++
  }
}

function handleDateSelect(dateString: string): void {
  if (!startDate.value || endDate.value) {
    // Start new selection
    startDate.value = dateString
    endDate.value = ''
  } else {
    // Complete selection
    let start = startDate.value
    let end = dateString
    if (dateString < startDate.value) {
      start = dateString
      end = startDate.value
    }
    startDate.value = start
    endDate.value = end
  }
}

function handleHover(date: string | null): void {
  hoverDate.value = date
}

watch(
  () => props.open,
  (isOpen) => {
    if (isOpen) {
      if (props.expense) {
        description.value = props.expense.description
        amount.value = props.expense.amount.toString()
        startDate.value = props.expense.startDate
        endDate.value = props.expense.endDate
      } else {
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

      // Initialize calendar to the start date's month
      if (startDate.value) {
        const [year, month] = startDate.value.split('-').map(Number) as [
          number,
          number,
        ]
        calendarYear.value = year
        calendarMonth.value = month - 1
      } else if (props.event.startDate) {
        const [year, month] = props.event.startDate.split('-').map(Number) as [
          number,
          number,
        ]
        calendarYear.value = year
        calendarMonth.value = month - 1
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
    if (props.expense) {
      await expensesStore.updateExpense(props.expense.id, {
        description: desc,
        amount: amt,
        startDate: startDate.value,
        endDate: endDate.value,
      })
    } else {
      await expensesStore.createExpense(
        props.event.id,
        desc,
        amt,
        startDate.value,
        endDate.value
      )
    }
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
  <BaseModal :open="open" :title="modalTitle" size="lg" @close="handleClose">
    <form class="space-y-4" @submit.prevent="handleSubmit">
      <FormInput
        id="expense-description"
        v-model="description"
        label="Description"
        placeholder="What was this expense for?"
        data-testid="expense-description-input"
        autofocus
        :disabled="submitting"
      />

      <FormInput
        id="expense-amount"
        v-model="amount"
        label="Amount"
        placeholder="0.00"
        data-testid="expense-amount-input"
        prefix="€"
        inputmode="decimal"
        :disabled="submitting"
      />

      <div v-if="eventHasDates || isEditing">
        <label
          class="mb-2 block text-sm font-medium text-gray-700 dark:text-stone-300"
        >
          Dates
        </label>

        <div
          class="rounded-xl border border-gray-200 bg-gray-50 p-4 dark:border-stone-700 dark:bg-stone-800"
        >
          <!-- Month header with navigation -->
          <div class="mb-2 flex items-center justify-between">
            <IconButton
              label="Previous month"
              :disabled="!canNavigatePrev"
              class="rounded-md p-1.5 hover:bg-gray-200 dark:hover:bg-white/10"
              @click="navigatePrev"
            >
              <ChevronLeftIcon class="size-5" />
            </IconButton>
            <span class="text-sm font-semibold text-gray-900 dark:text-white">
              {{ monthLabel }}
            </span>
            <IconButton
              label="Next month"
              :disabled="!canNavigateNext"
              class="rounded-md p-1.5 hover:bg-gray-200 dark:hover:bg-white/10"
              @click="navigateNext"
            >
              <ChevronRightIcon class="size-5" />
            </IconButton>
          </div>

          <CalendarMonth
            :year="calendarYear"
            :month="calendarMonth"
            :selected-start="startDate || null"
            :selected-end="endDate || null"
            :hover-date="hoverDate"
            :min-date="event.startDate ?? undefined"
            :max-date="event.endDate ?? undefined"
            hide-header
            @select="handleDateSelect"
            @hover="handleHover"
          />

          <!-- Selection summary -->
          <div
            class="mt-2 text-center text-sm text-gray-500 dark:text-stone-400"
          >
            {{ selectionText }}
          </div>
        </div>
      </div>

      <FormActions
        :submit-label="isEditing ? 'Save' : 'Add Expense'"
        :loading-label="isEditing ? 'Saving...' : 'Adding...'"
        :loading="submitting"
        :disabled="!description.trim() || !(parseFloat(amount) > 0)"
        @cancel="handleClose"
      />
    </form>
  </BaseModal>
</template>
