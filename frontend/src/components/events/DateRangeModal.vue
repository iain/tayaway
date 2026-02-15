<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { ChevronLeftIcon, ChevronRightIcon } from '@heroicons/vue/24/outline'
import BaseModal from '@/components/common/BaseModal.vue'
import CalendarMonth from '@/components/calendar/CalendarMonth.vue'
import { useCalendar } from '@/composables/useCalendar'

export interface DateRangeItem {
  start_date: string
  end_date: string
}

const props = defineProps<{
  open: boolean
  preselectedStart?: string | null
  preselectedEnd?: string | null
  existingRanges?: DateRangeItem[]
}>()

const emit = defineEmits<{
  close: []
  save: [start: string, end: string]
}>()

const { formatDateDisplay } = useCalendar()

// State for the two calendars
const today = new Date()
const leftYear = ref(today.getFullYear())
const leftMonth = ref(today.getMonth())

const rightYear = computed(() => {
  if (leftMonth.value === 11) {
    return leftYear.value + 1
  }
  return leftYear.value
})

const rightMonth = computed(() => {
  return (leftMonth.value + 1) % 12
})

// Selection state
const selectedStart = ref<string | null>(null)
const selectedEnd = ref<string | null>(null)
const hoverDate = ref<string | null>(null)

// Watch for preselected values
watch(
  () => props.open,
  (isOpen) => {
    if (isOpen) {
      selectedStart.value = props.preselectedStart ?? null
      selectedEnd.value = props.preselectedEnd ?? null

      // If we have a preselected start, navigate to that month
      if (props.preselectedStart) {
        const [year, month] = props.preselectedStart.split('-').map(Number) as [
          number,
          number,
        ]
        leftYear.value = year
        leftMonth.value = month - 1
      } else {
        // Reset to current month
        leftYear.value = today.getFullYear()
        leftMonth.value = today.getMonth()
      }
    }
  },
  { immediate: true }
)

function navigatePrev(): void {
  if (leftMonth.value === 0) {
    leftMonth.value = 11
    leftYear.value--
  } else {
    leftMonth.value--
  }
}

function navigateNext(): void {
  if (leftMonth.value === 11) {
    leftMonth.value = 0
    leftYear.value++
  } else {
    leftMonth.value++
  }
}

function handleDateSelect(dateString: string): void {
  if (!selectedStart.value || selectedEnd.value) {
    // Start new selection
    selectedStart.value = dateString
    selectedEnd.value = null
  } else {
    // Complete selection
    let start = selectedStart.value
    let end = dateString
    if (dateString < selectedStart.value) {
      start = dateString
      end = selectedStart.value
    }
    selectedStart.value = start
    selectedEnd.value = end
    // Auto-save and close
    emit('save', start, end)
  }
}

function handleHover(date: string | null): void {
  hoverDate.value = date
}

function handleSave(): void {
  if (selectedStart.value && selectedEnd.value) {
    emit('save', selectedStart.value, selectedEnd.value)
  }
}

function handleClose(): void {
  emit('close')
}

const canSave = computed(() => selectedStart.value && selectedEnd.value)

const selectionText = computed(() => {
  if (selectedStart.value && selectedEnd.value) {
    return `${formatDateDisplay(selectedStart.value)} - ${formatDateDisplay(selectedEnd.value)}`
  }
  if (selectedStart.value) {
    return `${formatDateDisplay(selectedStart.value)} - Select end date`
  }
  return 'Select start date'
})
</script>

<template>
  <BaseModal
    :open="open"
    title="Select Date Range"
    size="2xl"
    @close="handleClose"
  >
    <div class="mb-4 text-sm text-gray-500 dark:text-stone-400">
      {{ selectionText }}
    </div>

    <!-- Navigation -->
    <div class="mb-4 flex items-center justify-between">
      <button
        type="button"
        class="rounded-md p-2 text-gray-500 hover:bg-gray-100 hover:text-gray-700 dark:text-stone-400 dark:hover:bg-white/10 dark:hover:text-stone-300"
        @click="navigatePrev"
      >
        <ChevronLeftIcon class="size-5" />
      </button>
      <button
        type="button"
        class="rounded-md p-2 text-gray-500 hover:bg-gray-100 hover:text-gray-700 dark:text-stone-400 dark:hover:bg-white/10 dark:hover:text-stone-300"
        @click="navigateNext"
      >
        <ChevronRightIcon class="size-5" />
      </button>
    </div>

    <!-- Two calendars side by side -->
    <div class="grid grid-cols-1 gap-8 sm:grid-cols-2">
      <CalendarMonth
        :year="leftYear"
        :month="leftMonth"
        :selected-start="selectedStart"
        :selected-end="selectedEnd"
        :hover-date="hoverDate"
        :existing-ranges="existingRanges"
        @select="handleDateSelect"
        @hover="handleHover"
      />
      <CalendarMonth
        :year="rightYear"
        :month="rightMonth"
        :selected-start="selectedStart"
        :selected-end="selectedEnd"
        :hover-date="hoverDate"
        :existing-ranges="existingRanges"
        @select="handleDateSelect"
        @hover="handleHover"
      />
    </div>

    <div class="mt-6 flex items-center justify-end gap-x-6">
      <button
        type="button"
        class="text-sm/6 font-semibold text-gray-900 dark:text-white"
        @click="handleClose"
      >
        Cancel
      </button>
      <button
        type="button"
        data-testid="modal-save-button"
        class="rounded-md bg-rose-500 px-3 py-2 text-sm font-semibold text-white hover:bg-rose-400 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-rose-500 disabled:cursor-not-allowed disabled:opacity-50"
        :disabled="!canSave"
        @click="handleSave"
      >
        Add Range
      </button>
    </div>
  </BaseModal>
</template>
