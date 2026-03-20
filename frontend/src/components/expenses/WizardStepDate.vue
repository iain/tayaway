<script setup lang="ts">
import { ref, computed } from 'vue'
import { ChevronLeftIcon, ChevronRightIcon } from '@heroicons/vue/24/outline'
import IconButton from '@/components/common/IconButton.vue'
import CalendarMonth from '@/components/calendar/CalendarMonth.vue'
import { useCalendar, getMonthName } from '@/composables/useCalendar'
import type { PoolEvent } from '@/types/pool'

const props = defineProps<{
  event: PoolEvent
  calendarYear: number
  calendarMonth: number
  singleDate: boolean
}>()

const emit = defineEmits<{
  'update:calendarYear': [year: number]
  'update:calendarMonth': [month: number]
  'update:singleDate': [value: boolean]
}>()

const startDate = defineModel<string>('startDate', { required: true })
const endDate = defineModel<string>('endDate', { required: true })

const { formatDateDisplay } = useCalendar()
const hoverDate = ref<string | null>(null)

const monthLabel = computed(
  () => `${getMonthName(props.calendarMonth)} ${props.calendarYear}`
)

const canNavigatePrev = computed(() => {
  if (!props.event.startDate) return true
  const [minYear, minMonth] = props.event.startDate.split('-').map(Number) as [
    number,
    number,
  ]
  return (
    props.calendarYear > minYear ||
    (props.calendarYear === minYear && props.calendarMonth > minMonth - 1)
  )
})

const canNavigateNext = computed(() => {
  if (!props.event.endDate) return true
  const [maxYear, maxMonth] = props.event.endDate.split('-').map(Number) as [
    number,
    number,
  ]
  return (
    props.calendarYear < maxYear ||
    (props.calendarYear === maxYear && props.calendarMonth < maxMonth - 1)
  )
})

function navigatePrev(): void {
  if (!canNavigatePrev.value) return
  if (props.calendarMonth === 0) {
    emit('update:calendarMonth', 11)
    emit('update:calendarYear', props.calendarYear - 1)
  } else {
    emit('update:calendarMonth', props.calendarMonth - 1)
  }
}

function navigateNext(): void {
  if (!canNavigateNext.value) return
  if (props.calendarMonth === 11) {
    emit('update:calendarMonth', 0)
    emit('update:calendarYear', props.calendarYear + 1)
  } else {
    emit('update:calendarMonth', props.calendarMonth + 1)
  }
}

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

function handleDateSelect(dateString: string): void {
  if (props.singleDate) {
    startDate.value = dateString
    endDate.value = dateString
    return
  }

  if (!startDate.value || endDate.value) {
    startDate.value = dateString
    endDate.value = ''
  } else {
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

function toggleMode(): void {
  emit('update:singleDate', !props.singleDate)
  // When switching to single date mode, collapse to start date
  if (!props.singleDate && startDate.value) {
    endDate.value = startDate.value
  }
}
</script>

<template>
  <div>
    <div class="mb-3 flex items-center justify-between">
      <label class="text-sm font-medium text-gray-700 dark:text-stone-300">
        Expense period
      </label>
      <button
        type="button"
        class="text-xs font-medium text-cyan-600 hover:text-cyan-700 dark:text-cyan-400 dark:hover:text-cyan-300"
        data-testid="toggle-date-mode"
        @click="toggleMode"
      >
        {{ singleDate ? 'Date range' : 'Single date' }}
      </button>
    </div>

    <div
      class="rounded-xl border border-gray-200 bg-gray-50 p-4 dark:border-stone-700 dark:bg-stone-800"
    >
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

      <div class="mt-2 text-center text-sm text-gray-500 dark:text-stone-400">
        {{ selectionText }}
      </div>
    </div>
  </div>
</template>
