<script setup lang="ts">
import { computed } from 'vue'
import { useCalendar, type CalendarDay } from '@/composables/useCalendar'
import type { DateRangeItem } from '@/components/events/DateRangeList.vue'

const props = defineProps<{
  year: number
  month: number
  selectedStart: string | null
  selectedEnd: string | null
  hoverDate: string | null
  existingRanges?: DateRangeItem[]
  minDate?: string
  maxDate?: string
  hideHeader?: boolean
}>()

const emit = defineEmits<{
  select: [date: string]
  hover: [date: string | null]
}>()

const { getDaysInMonth, getMonthName, isDateInRange, isDateInHoverRange } =
  useCalendar()

const days = computed<CalendarDay[]>(() =>
  getDaysInMonth(props.year, props.month)
)

const monthName = computed(() => getMonthName(props.month))

const weekDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']

function isInSelectedRange(dateString: string): boolean {
  return isDateInRange(dateString, props.selectedStart, props.selectedEnd)
}

function isInHoverRange(dateString: string): boolean {
  if (props.selectedEnd || !props.selectedStart) return false
  return isDateInHoverRange(dateString, props.selectedStart, props.hoverDate)
}

function getHoverRangeBounds(): { start: string; end: string } | null {
  if (props.selectedEnd || !props.selectedStart || !props.hoverDate) return null
  const start =
    props.selectedStart < props.hoverDate
      ? props.selectedStart
      : props.hoverDate
  const end =
    props.selectedStart < props.hoverDate
      ? props.hoverDate
      : props.selectedStart
  return { start, end }
}

function getExistingRangeInfo(dateString: string): {
  inRange: boolean
  isStart: boolean
  isEnd: boolean
} {
  if (!props.existingRanges?.length)
    return { inRange: false, isStart: false, isEnd: false }

  let inRange = false
  let isStart = false
  let isEnd = false

  for (const range of props.existingRanges) {
    if (dateString >= range.start_date && dateString <= range.end_date) {
      inRange = true
      if (dateString === range.start_date) isStart = true
      if (dateString === range.end_date) isEnd = true
    }
  }

  return { inRange, isStart, isEnd }
}

function isDisabled(dateString: string): boolean {
  if (props.minDate && dateString < props.minDate) return true
  if (props.maxDate && dateString > props.maxDate) return true
  return false
}

function getDayClasses(dateString: string): string[] {
  if (isDisabled(dateString)) {
    return ['opacity-30', 'cursor-default']
  }

  // Selected range (both start and end chosen)
  if (isInSelectedRange(dateString)) {
    const classes = ['bg-rose-500', 'font-semibold', 'text-white']
    if (dateString === props.selectedStart) classes.push('rounded-l-full')
    if (dateString === props.selectedEnd) classes.push('rounded-r-full')
    return classes
  }

  // Only start selected (waiting for end) — keep start solid
  if (!props.selectedEnd && dateString === props.selectedStart) {
    const bounds = getHoverRangeBounds()
    const classes = ['bg-rose-500', 'font-semibold', 'text-white']
    if (bounds) {
      if (dateString === bounds.start) classes.push('rounded-l-full')
      if (dateString === bounds.end) classes.push('rounded-r-full')
    } else {
      classes.push('rounded-full')
    }
    return classes
  }

  // Hover range (preview — lighter than committed selection)
  if (isInHoverRange(dateString)) {
    const bounds = getHoverRangeBounds()
    const classes = ['bg-rose-400/60', 'text-white']
    if (bounds && dateString === bounds.start) classes.push('rounded-l-full')
    if (bounds && dateString === bounds.end) classes.push('rounded-r-full')
    return classes
  }

  // Existing ranges (distinct color from selection)
  const existing = getExistingRangeInfo(dateString)
  if (existing.inRange) {
    const classes = ['bg-sky-500/30']
    if (existing.isStart) classes.push('rounded-l-full')
    if (existing.isEnd) classes.push('rounded-r-full')
    return classes
  }

  return ['hover:bg-white/10']
}

function handleClick(day: CalendarDay): void {
  if (isDisabled(day.dateString)) return
  emit('select', day.dateString)
}

function handleMouseEnter(day: CalendarDay): void {
  if (isDisabled(day.dateString)) return
  emit('hover', day.dateString)
}

function handleMouseLeave(): void {
  emit('hover', null)
}
</script>

<template>
  <div class="w-full">
    <div
      v-if="!hideHeader"
      class="mb-4 text-center font-semibold text-gray-900 dark:text-white"
    >
      {{ monthName }} {{ year }}
    </div>

    <div
      class="mb-1 grid grid-cols-7 text-center text-xs font-medium text-gray-500 dark:text-stone-400"
    >
      <div v-for="day in weekDays" :key="day" class="py-1.5">
        {{ day }}
      </div>
    </div>

    <div class="grid grid-cols-7">
      <button
        v-for="day in days"
        :key="day.dateString"
        :data-testid="`calendar-day-${day.dateString}`"
        type="button"
        class="relative aspect-square text-sm transition-colors duration-100 focus-visible:z-10 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
        :class="[
          day.isCurrentMonth
            ? 'text-gray-900 dark:text-white'
            : 'text-gray-400 dark:text-gray-600',
          getDayClasses(day.dateString),
        ]"
        @click="handleClick(day)"
        @mouseenter="handleMouseEnter(day)"
        @mouseleave="handleMouseLeave"
      >
        {{ day.date.getDate() }}
      </button>
    </div>
  </div>
</template>
