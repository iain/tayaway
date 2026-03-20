<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import BaseModal from '@/components/common/BaseModal.vue'
import FormActions from '@/components/form/FormActions.vue'
import WizardStepDetails from '@/components/expenses/WizardStepDetails.vue'
import WizardStepDate from '@/components/expenses/WizardStepDate.vue'
import WizardStepPeople from '@/components/expenses/WizardStepPeople.vue'
import { useExpensesStore } from '@/stores/expenses'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useAuthStore } from '@/stores/auth'
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

// Wizard state
const step = ref(1)

// Steps: Details → Date (if event has dates or editing) → People
const showDateStep = computed(
  () =>
    (props.event.startDate != null && props.event.endDate != null) ||
    props.expense != null
)
const steps = computed(() => {
  const s = ['details']
  if (showDateStep.value) s.push('date')
  s.push('people')
  return s
})
const totalSteps = computed(() => steps.value.length)
const currentStepName = computed(() => steps.value[step.value - 1])

// Form state
const description = ref('')
const amount = ref('')
const startDate = ref('')
const endDate = ref('')
const singleDate = ref(true)
const submitting = ref(false)

// Calendar navigation state
const calendarYear = ref(new Date().getFullYear())
const calendarMonth = ref(new Date().getMonth())

// People state
const everyone = ref(true)
const selectedUserIds = ref<string[]>([])

const isEditing = computed(() => props.expense != null)

const modalTitle = computed(() =>
  isEditing.value ? 'Edit Expense' : 'Add Expense'
)

const eventHasDates = computed(
  () => props.event.startDate != null && props.event.endDate != null
)

// Step validation
const detailsValid = computed(() => {
  const desc = description.value.trim()
  const amt = parseFloat(amount.value)
  return desc.length > 0 && !isNaN(amt) && amt > 0
})

const dateValid = computed(() => {
  return !!startDate.value && !!endDate.value
})

const canProceed = computed(() => {
  if (currentStepName.value === 'details') return detailsValid.value
  if (currentStepName.value === 'date') return dateValid.value
  if (currentStepName.value === 'people') {
    // In specific-people mode, require at least one person selected
    return everyone.value || selectedUserIds.value.length > 0
  }
  return true
})

const submitLabel = computed(() => {
  if (step.value < totalSteps.value) return 'Next'
  return isEditing.value ? 'Save' : 'Add Expense'
})

const loadingLabel = computed(() => {
  return isEditing.value ? 'Saving...' : 'Adding...'
})

function nextStep(): void {
  if (step.value < totalSteps.value) {
    step.value++
  }
}

function prevStep(): void {
  if (step.value > 1) {
    step.value--
  }
}

watch(
  () => props.open,
  (isOpen) => {
    if (isOpen) {
      step.value = 1

      if (props.expense) {
        description.value = props.expense.description
        amount.value = props.expense.amount.toString()
        startDate.value = props.expense.startDate
        endDate.value = props.expense.endDate
        singleDate.value = props.expense.startDate === props.expense.endDate

        // Load existing participants
        const participantIds = props.expense.participantIds ?? []
        if (participantIds.length > 0) {
          everyone.value = false
          selectedUserIds.value = participantIds
            .map((pid) => pool.get('expenseParticipant', pid)?.userId)
            .filter((uid): uid is string => uid !== undefined)
        } else {
          everyone.value = true
          selectedUserIds.value = []
        }
      } else {
        description.value = ''
        amount.value = ''
        everyone.value = true
        selectedUserIds.value = []
        singleDate.value = true

        if (eventHasDates.value) {
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
            singleDate.value = rsvp.startDate === rsvp.endDate
          } else {
            startDate.value = props.event.startDate!
            endDate.value = props.event.endDate!
            singleDate.value = props.event.startDate === props.event.endDate
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
  if (step.value < totalSteps.value) {
    nextStep()
    return
  }

  const desc = description.value.trim()
  const amt = parseFloat(amount.value)
  if (!desc || isNaN(amt) || amt <= 0) return
  if (!startDate.value || !endDate.value) return

  const participantIds =
    !everyone.value && selectedUserIds.value.length > 0
      ? selectedUserIds.value
      : undefined

  submitting.value = true
  try {
    if (props.expense) {
      await expensesStore.updateExpense(props.expense.id, {
        description: desc,
        amount: amt,
        startDate: startDate.value,
        endDate: endDate.value,
        participantIds: participantIds ?? [],
      })
    } else {
      await expensesStore.createExpense(
        props.event.id,
        desc,
        amt,
        startDate.value,
        endDate.value,
        participantIds
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
  <BaseModal
    :open="open"
    :title="modalTitle"
    size="lg"
    :prevent-close="submitting"
    @close="handleClose"
  >
    <form class="space-y-4" @submit.prevent="handleSubmit">
      <!-- Step indicator -->
      <div
        role="group"
        :aria-label="`Step ${step} of ${totalSteps}`"
        class="flex items-center justify-center gap-2"
        data-testid="wizard-steps"
      >
        <div
          v-for="s in totalSteps"
          :key="s"
          role="img"
          :aria-label="`Step ${s}${s === step ? ' (current)' : s < step ? ' (completed)' : ''}`"
          class="size-2 rounded-full"
          :class="
            s === step
              ? 'bg-rose-500'
              : s < step
                ? 'bg-rose-300 dark:bg-rose-700'
                : 'bg-gray-300 dark:bg-stone-600'
          "
        />
      </div>

      <!-- Step 1: Details -->
      <WizardStepDetails
        v-if="currentStepName === 'details'"
        v-model:description="description"
        v-model:amount="amount"
        :disabled="submitting"
      />

      <!-- Step 2: Date (only when event has dates or editing) -->
      <WizardStepDate
        v-if="currentStepName === 'date'"
        v-model:start-date="startDate"
        v-model:end-date="endDate"
        :event="event"
        :calendar-year="calendarYear"
        :calendar-month="calendarMonth"
        :single-date="singleDate"
        @update:calendar-year="calendarYear = $event"
        @update:calendar-month="calendarMonth = $event"
        @update:single-date="singleDate = $event"
      />

      <!-- Step: People -->
      <WizardStepPeople
        v-if="currentStepName === 'people'"
        v-model:selected-user-ids="selectedUserIds"
        :event="event"
        :start-date="startDate"
        :end-date="endDate"
        :everyone="everyone"
        @update:everyone="everyone = $event"
      />

      <FormActions
        :submit-label="submitLabel"
        :loading-label="loadingLabel"
        :loading="submitting"
        :disabled="!canProceed"
        :cancel-label="step > 1 ? 'Back' : 'Cancel'"
        @cancel="step > 1 ? prevStep() : handleClose()"
      />
    </form>
  </BaseModal>
</template>
