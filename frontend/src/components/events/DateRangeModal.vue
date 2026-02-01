<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import {
  Dialog,
  DialogPanel,
  DialogTitle,
  TransitionChild,
  TransitionRoot,
} from '@headlessui/vue'
import { ChevronLeftIcon, ChevronRightIcon, XMarkIcon } from '@heroicons/vue/24/outline'
import CalendarMonth from '@/components/calendar/CalendarMonth.vue'
import { useCalendar } from '@/composables/useCalendar'

const props = defineProps<{
  open: boolean
  preselectedStart?: string | null
  preselectedEnd?: string | null
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
watch(() => props.open, (isOpen) => {
  if (isOpen) {
    selectedStart.value = props.preselectedStart ?? null
    selectedEnd.value = props.preselectedEnd ?? null

    // If we have a preselected start, navigate to that month
    if (props.preselectedStart) {
      const [year, month] = props.preselectedStart.split('-').map(Number)
      leftYear.value = year
      leftMonth.value = month - 1
    } else {
      // Reset to current month
      leftYear.value = today.getFullYear()
      leftMonth.value = today.getMonth()
    }
  }
}, { immediate: true })

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
    if (dateString < selectedStart.value) {
      // User clicked earlier date, swap them
      selectedEnd.value = selectedStart.value
      selectedStart.value = dateString
    } else {
      selectedEnd.value = dateString
    }
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
  <TransitionRoot
    as="template"
    :show="open"
  >
    <Dialog
      class="relative z-50"
      @close="handleClose"
    >
      <TransitionChild
        as="template"
        enter="ease-out duration-300"
        enter-from="opacity-0"
        enter-to="opacity-100"
        leave="ease-in duration-200"
        leave-from="opacity-100"
        leave-to="opacity-0"
      >
        <div class="fixed inset-0 bg-gray-500/75 dark:bg-gray-900/75 transition-opacity" />
      </TransitionChild>

      <div class="fixed inset-0 z-10 overflow-y-auto">
        <div class="flex min-h-full items-end justify-center p-4 text-center sm:items-center sm:p-0">
          <TransitionChild
            as="template"
            enter="ease-out duration-300"
            enter-from="opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"
            enter-to="opacity-100 translate-y-0 sm:scale-100"
            leave="ease-in duration-200"
            leave-from="opacity-100 translate-y-0 sm:scale-100"
            leave-to="opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"
          >
            <DialogPanel class="relative transform overflow-hidden rounded-lg bg-white dark:bg-gray-800 px-4 pb-4 pt-5 text-left shadow-xl transition-all sm:my-8 sm:w-full sm:max-w-2xl sm:p-6">
              <div class="absolute right-0 top-0 pr-4 pt-4">
                <button
                  type="button"
                  class="rounded-md bg-white dark:bg-gray-800 text-gray-400 hover:text-gray-500 dark:hover:text-gray-300 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2"
                  @click="handleClose"
                >
                  <span class="sr-only">Close</span>
                  <XMarkIcon
                    class="size-6"
                    aria-hidden="true"
                  />
                </button>
              </div>

              <div class="sm:flex sm:items-start">
                <div class="w-full">
                  <DialogTitle
                    as="h3"
                    class="text-lg font-semibold text-gray-900 dark:text-white mb-4"
                  >
                    Select Date Range
                  </DialogTitle>

                  <div class="text-sm text-gray-600 dark:text-gray-400 mb-4">
                    {{ selectionText }}
                  </div>

                  <!-- Navigation -->
                  <div class="flex items-center justify-between mb-4">
                    <button
                      type="button"
                      class="p-2 rounded-md text-gray-400 hover:text-gray-500 dark:hover:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700"
                      @click="navigatePrev"
                    >
                      <ChevronLeftIcon class="size-5" />
                    </button>
                    <button
                      type="button"
                      class="p-2 rounded-md text-gray-400 hover:text-gray-500 dark:hover:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700"
                      @click="navigateNext"
                    >
                      <ChevronRightIcon class="size-5" />
                    </button>
                  </div>

                  <!-- Two calendars side by side -->
                  <div class="grid grid-cols-1 sm:grid-cols-2 gap-8">
                    <CalendarMonth
                      :year="leftYear"
                      :month="leftMonth"
                      :selected-start="selectedStart"
                      :selected-end="selectedEnd"
                      :hover-date="hoverDate"
                      @select="handleDateSelect"
                      @hover="handleHover"
                    />
                    <CalendarMonth
                      :year="rightYear"
                      :month="rightMonth"
                      :selected-start="selectedStart"
                      :selected-end="selectedEnd"
                      :hover-date="hoverDate"
                      @select="handleDateSelect"
                      @hover="handleHover"
                    />
                  </div>
                </div>
              </div>

              <div class="mt-6 sm:flex sm:flex-row-reverse gap-3">
                <button
                  type="button"
                  data-testid="modal-save-button"
                  class="inline-flex w-full justify-center rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed sm:w-auto"
                  :disabled="!canSave"
                  @click="handleSave"
                >
                  Add Range
                </button>
                <button
                  type="button"
                  class="mt-3 inline-flex w-full justify-center rounded-md bg-white dark:bg-gray-700 px-3 py-2 text-sm font-semibold text-gray-900 dark:text-white shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-gray-600 hover:bg-gray-50 dark:hover:bg-gray-600 sm:mt-0 sm:w-auto"
                  @click="handleClose"
                >
                  Cancel
                </button>
              </div>
            </DialogPanel>
          </TransitionChild>
        </div>
      </div>
    </Dialog>
  </TransitionRoot>
</template>
