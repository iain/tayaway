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
    <div class="mb-3 flex flex-wrap items-center justify-between gap-2">
      <p class="text-sm font-medium text-ink">Expense period</p>
      <div
        class="inline-flex gap-0.5 rounded-lg bg-btn-secondary-fill p-0.5"
        data-testid="toggle-date-mode"
      >
        <button
          type="button"
          class="cursor-pointer rounded-md px-3 py-1.5 text-xs font-medium transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
          :class="
            singleDate
              ? 'bg-amber-100 text-amber-800 shadow-sm dark:bg-amber-900/40 dark:text-amber-300'
              : 'text-ink-muted hover:bg-gray-200 hover:text-gray-700 dark:hover:bg-stone-600 dark:hover:text-stone-200'
          "
          @click="singleDate || toggleMode()"
        >
          Single date
        </button>
        <button
          type="button"
          class="cursor-pointer rounded-md px-3 py-1.5 text-xs font-medium transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
          :class="
            !singleDate
              ? 'bg-amber-100 text-amber-800 shadow-sm dark:bg-amber-900/40 dark:text-amber-300'
              : 'text-ink-muted hover:bg-gray-200 hover:text-gray-700 dark:hover:bg-stone-600 dark:hover:text-stone-200'
          "
          @click="singleDate && toggleMode()"
        >
          Date range
        </button>
      </div>
    </div>

    <div class="rounded-xl border border-line bg-surface-sunken p-4">
      <div class="mb-2 flex items-center justify-between">
        <IconButton
          label="Previous month"
          :disabled="!canNavigatePrev"
          class="rounded-md p-1.5 hover:bg-gray-200 dark:hover:bg-white/10"
          @click="navigatePrev"
        >
          <ChevronLeftIcon class="size-5" />
        </IconButton>
        <span class="text-sm font-semibold text-ink">
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

      <div class="mt-2 text-center text-sm text-ink-muted">
        {{ selectionText }}
      </div>
    </div>
  </div>
</template>
