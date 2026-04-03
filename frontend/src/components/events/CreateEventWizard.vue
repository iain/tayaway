<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { useRouter } from 'vue-router'
import {
  CalendarDaysIcon,
  ChevronLeftIcon,
  ChevronRightIcon,
  UsersIcon,
} from '@heroicons/vue/24/outline'
import BaseModal from '@/components/common/BaseModal.vue'
import FormInput from '@/components/form/FormInput.vue'
import FormTextarea from '@/components/form/FormTextarea.vue'
import LocationInput from '@/components/form/LocationInput.vue'
import AppButton from '@/components/common/AppButton.vue'
import TextButton from '@/components/common/TextButton.vue'
import IconButton from '@/components/common/IconButton.vue'
import CalendarMonth from '@/components/calendar/CalendarMonth.vue'
import {
  useEventsStore,
  useDatePollsStore,
  useNotificationsStore,
} from '@/stores'
import { useCalendar } from '@/composables/useCalendar'

const props = defineProps<{
  open: boolean
}>()

const emit = defineEmits<{
  close: []
}>()

const router = useRouter()
const eventsStore = useEventsStore()
const datePollsStore = useDatePollsStore()
const { formatDateDisplay } = useCalendar()

// Wizard step
const step = ref(1)
const submitting = ref(false)

// Step 1: Details
const name = ref('')
const description = ref('')
const locationName = ref('')
const latitude = ref<number | null>(null)
const longitude = ref<number | null>(null)

// Step 2: Dates
type DateMode = null | 'known' | 'poll'
const dateMode = ref<DateMode>(null)

// Known dates state
const selectedStart = ref<string | null>(null)
const selectedEnd = ref<string | null>(null)
const hoverDate = ref<string | null>(null)

// Poll state
const pollDeadline = ref<string | null>(null)

// Calendar navigation (shared between both modes)
const today = new Date()
const calYear = ref(today.getFullYear())
const calMonth = ref(today.getMonth())

const rightYear = computed(() =>
  calMonth.value === 11 ? calYear.value + 1 : calYear.value
)
const rightMonth = computed(() => (calMonth.value + 1) % 12)

// Reset on open
watch(
  () => props.open,
  (isOpen) => {
    if (isOpen) {
      step.value = 1
      name.value = ''
      description.value = ''
      locationName.value = ''
      latitude.value = null
      longitude.value = null
      dateMode.value = null
      selectedStart.value = null
      selectedEnd.value = null
      hoverDate.value = null
      pollDeadline.value = null
      calYear.value = today.getFullYear()
      calMonth.value = today.getMonth()
    }
  }
)

// Validation
const step1Valid = computed(() => !!name.value.trim())

const canSubmit = computed(() => {
  if (!step1Valid.value) return false
  if (dateMode.value === 'known')
    return !!selectedStart.value && !!selectedEnd.value
  if (dateMode.value === 'poll') return !!pollDeadline.value
  // No dates — just create the event
  return true
})

const todayString = computed(() => {
  const d = new Date()
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
})

// Calendar navigation
function navigatePrev(): void {
  if (calMonth.value === 0) {
    calMonth.value = 11
    calYear.value--
  } else {
    calMonth.value--
  }
}

function navigateNext(): void {
  if (calMonth.value === 11) {
    calMonth.value = 0
    calYear.value++
  } else {
    calMonth.value++
  }
}

// Date range selection (known dates)
function handleRangeSelect(dateString: string): void {
  if (!selectedStart.value || selectedEnd.value) {
    selectedStart.value = dateString
    selectedEnd.value = null
  } else {
    let start = selectedStart.value
    let end = dateString
    if (dateString < selectedStart.value) {
      start = dateString
      end = selectedStart.value
    }
    selectedStart.value = start
    selectedEnd.value = end
  }
}

// Single date selection (poll deadline)
function handleDeadlineSelect(dateString: string): void {
  if (dateString < todayString.value) return
  pollDeadline.value = dateString
}

// Selection display text
const dateSelectionText = computed(() => {
  if (dateMode.value === 'known') {
    if (selectedStart.value && selectedEnd.value) {
      return `${formatDateDisplay(selectedStart.value)} — ${formatDateDisplay(selectedEnd.value)}`
    }
    if (selectedStart.value) {
      return `${formatDateDisplay(selectedStart.value)} — pick end date`
    }
    return 'Pick start date'
  }
  if (dateMode.value === 'poll') {
    if (pollDeadline.value) {
      return `Deadline: ${formatDateDisplay(pollDeadline.value)}`
    }
    return 'Pick a voting deadline'
  }
  return ''
})

// Navigation
function goToStep2(): void {
  if (step1Valid.value) step.value = 2
}

function goBack(): void {
  if (dateMode.value) {
    dateMode.value = null
  } else {
    step.value = 1
  }
}

function selectMode(mode: DateMode): void {
  dateMode.value = mode
  // Reset selections when switching modes
  selectedStart.value = null
  selectedEnd.value = null
  hoverDate.value = null
  pollDeadline.value = null
  calYear.value = today.getFullYear()
  calMonth.value = today.getMonth()
}

// Submit
async function handleSubmit(): Promise<void> {
  if (!canSubmit.value || submitting.value) return

  submitting.value = true
  try {
    const { eventId, queued } = await eventsStore.createEvent({
      name: name.value.trim(),
      description: description.value.trim() || undefined,
      startDate:
        dateMode.value === 'known' && selectedStart.value
          ? selectedStart.value
          : undefined,
      endDate:
        dateMode.value === 'known' && selectedEnd.value
          ? selectedEnd.value
          : undefined,
      locationName: locationName.value || undefined,
      latitude: latitude.value ?? undefined,
      longitude: longitude.value ?? undefined,
    })

    if (queued) {
      emit('close')
      useNotificationsStore().showInfo('Event will be created when back online')
      return
    }

    // If poll mode, also create the poll
    if (dateMode.value === 'poll' && pollDeadline.value) {
      try {
        await datePollsStore.createPoll(eventId, pollDeadline.value)
        emit('close')
        router.push(`/events/${eventId}/planning/date-ranges`)
        return
      } catch {
        // Event created but poll failed — still navigate to event
      }
    }

    emit('close')
    router.push(`/events/${eventId}`)
  } catch {
    // Error handled by store
  } finally {
    submitting.value = false
  }
}

const modalTitle = computed(() => {
  if (step.value === 1) return 'New Event'
  if (!dateMode.value) return 'When is it?'
  if (dateMode.value === 'known') return 'Pick your dates'
  return 'Set voting deadline'
})

const submitLabel = computed(() => {
  if (dateMode.value === 'poll') return 'Create Event & Open Poll'
  return 'Create Event'
})
</script>

<template>
  <BaseModal
    :open="open"
    :title="modalTitle"
    size="2xl"
    :prevent-close="submitting"
    @close="emit('close')"
  >
    <!-- Step 1: Details -->
    <div v-if="step === 1">
      <form class="space-y-4" @submit.prevent="goToStep2">
        <FormInput
          id="event-name"
          v-model="name"
          label="Name"
          placeholder="e.g. Summer trip to Portugal"
          autocomplete="off"
          autofocus
          required
          :maxlength="255"
          :disabled="submitting"
        />
        <FormTextarea
          id="event-description"
          v-model="description"
          label="Description (optional)"
          placeholder="What's the plan?"
          :rows="2"
          :disabled="submitting"
        />
        <LocationInput
          v-model="locationName"
          v-model:latitude="latitude"
          v-model:longitude="longitude"
          label="Location (optional)"
          :disabled="submitting"
        />

        <div class="flex items-center justify-end gap-3 pt-2">
          <TextButton variant="secondary" @click="emit('close')">
            Cancel
          </TextButton>
          <AppButton type="submit" :disabled="!step1Valid"> Next </AppButton>
        </div>
      </form>
    </div>

    <!-- Step 2: Date choice -->
    <div v-else-if="step === 2 && !dateMode">
      <p class="mb-5 text-sm text-gray-500 dark:text-stone-400">
        Do you already know the dates, or should members vote?
      </p>

      <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <button
          type="button"
          class="cursor-pointer rounded-lg border border-gray-200 p-4 text-left transition-colors hover:border-amber-300 hover:bg-amber-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-rose-500 dark:border-stone-700 dark:hover:border-amber-700 dark:hover:bg-amber-900/10"
          @click="selectMode('known')"
        >
          <CalendarDaysIcon
            class="mb-2 size-6 text-amber-600 dark:text-amber-400"
          />
          <p class="text-sm font-semibold text-gray-900 dark:text-white">
            I know the dates
          </p>
          <p class="mt-0.5 text-xs text-gray-500 dark:text-stone-400">
            Set start and end dates now
          </p>
        </button>
        <button
          type="button"
          class="cursor-pointer rounded-lg border border-gray-200 p-4 text-left transition-colors hover:border-amber-300 hover:bg-amber-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-rose-500 dark:border-stone-700 dark:hover:border-amber-700 dark:hover:bg-amber-900/10"
          @click="selectMode('poll')"
        >
          <UsersIcon class="mb-2 size-6 text-amber-600 dark:text-amber-400" />
          <p class="text-sm font-semibold text-gray-900 dark:text-white">
            Let members vote
          </p>
          <p class="mt-0.5 text-xs text-gray-500 dark:text-stone-400">
            Open a date poll with a deadline
          </p>
        </button>
      </div>

      <div class="mt-6 flex items-center justify-between">
        <TextButton variant="secondary" @click="goBack"> Back </TextButton>
        <AppButton
          variant="secondary"
          :loading="submitting"
          @click="handleSubmit"
        >
          Skip — no dates yet
        </AppButton>
      </div>
    </div>

    <!-- Step 2b: Known dates — calendar range picker -->
    <div v-else-if="step === 2 && dateMode === 'known'">
      <div class="mb-4 text-sm text-gray-500 dark:text-stone-400">
        {{ dateSelectionText }}
      </div>

      <div class="mb-4 flex items-center justify-between">
        <IconButton label="Previous month" @click="navigatePrev">
          <ChevronLeftIcon class="size-5" />
        </IconButton>
        <IconButton label="Next month" @click="navigateNext">
          <ChevronRightIcon class="size-5" />
        </IconButton>
      </div>

      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 sm:gap-8">
        <CalendarMonth
          :year="calYear"
          :month="calMonth"
          :selected-start="selectedStart"
          :selected-end="selectedEnd"
          :hover-date="hoverDate"
          @select="handleRangeSelect"
          @hover="hoverDate = $event"
        />
        <CalendarMonth
          :year="rightYear"
          :month="rightMonth"
          :selected-start="selectedStart"
          :selected-end="selectedEnd"
          :hover-date="hoverDate"
          @select="handleRangeSelect"
          @hover="hoverDate = $event"
        />
      </div>

      <div class="mt-6 flex items-center justify-between">
        <TextButton variant="secondary" @click="goBack"> Back </TextButton>
        <AppButton
          :disabled="!canSubmit"
          :loading="submitting"
          @click="handleSubmit"
        >
          {{ submitLabel }}
        </AppButton>
      </div>
    </div>

    <!-- Step 2c: Poll — single date picker for deadline -->
    <div v-else-if="step === 2 && dateMode === 'poll'">
      <div class="mb-4 text-sm text-gray-500 dark:text-stone-400">
        {{ dateSelectionText }}
      </div>

      <div class="mb-4 flex items-center justify-between">
        <IconButton label="Previous month" @click="navigatePrev">
          <ChevronLeftIcon class="size-5" />
        </IconButton>
        <IconButton label="Next month" @click="navigateNext">
          <ChevronRightIcon class="size-5" />
        </IconButton>
      </div>

      <div class="mx-auto max-w-xs">
        <CalendarMonth
          :year="calYear"
          :month="calMonth"
          :selected-start="pollDeadline"
          :selected-end="pollDeadline"
          :hover-date="null"
          :min-date="todayString"
          @select="handleDeadlineSelect"
        />
      </div>

      <div class="mt-6 flex items-center justify-between">
        <TextButton variant="secondary" @click="goBack"> Back </TextButton>
        <AppButton
          :disabled="!canSubmit"
          :loading="submitting"
          @click="handleSubmit"
        >
          {{ submitLabel }}
        </AppButton>
      </div>
    </div>
  </BaseModal>
</template>
