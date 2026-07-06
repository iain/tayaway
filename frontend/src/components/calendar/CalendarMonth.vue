<script setup lang="ts">
import { computed, ref } from 'vue'
import { useCalendar, type CalendarDay } from '@/composables/useCalendar'
import { addDays } from '@/utils/date'
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
  // When provided, the calendar switches to multi-select mode: each listed day
  // is highlighted and clicking a day toggles it (the parent owns the set).
  // Range/hover selection is bypassed in this mode.
  selectedDates?: string[]
}>()

const isMultiSelect = computed(() => props.selectedDates !== undefined)

const emit = defineEmits<{
  select: [date: string]
  selectRange: [from: string, to: string]
  hover: [date: string | null]
}>()

// Multi-select state (RSVP day picker). `anchor` is the last clicked day;
// shift-clicking selects the whole range from the anchor to the clicked day
// (still stored as individual days). Hover with shift held previews that range.
const selectedSet = computed(() => new Set(props.selectedDates ?? []))
const anchor = ref<string | null>(null)
const internalHover = ref<string | null>(null)
const internalHoverShift = ref(false)

const shiftPreviewBounds = computed<{ start: string; end: string } | null>(
  () => {
    if (
      !isMultiSelect.value ||
      !internalHoverShift.value ||
      !anchor.value ||
      !internalHover.value
    )
      return null
    const a = anchor.value
    const h = internalHover.value
    return a <= h ? { start: a, end: h } : { start: h, end: a }
  }
)

function isInShiftPreview(dateString: string): boolean {
  const b = shiftPreviewBounds.value
  return b !== null && dateString >= b.start && dateString <= b.end
}

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

  // Multi-select mode (RSVP day picker): selected days fill their cell and
  // merge with adjacent selected days into a continuous pill; a shift-drag
  // shows a lighter range preview of what would be added.
  if (isMultiSelect.value) {
    if (selectedSet.value.has(dateString)) {
      const prevSelected = selectedSet.value.has(addDays(dateString, -1))
      const nextSelected = selectedSet.value.has(addDays(dateString, 1))
      const classes = ['bg-rose-500', 'font-semibold', 'text-white']
      if (!prevSelected && !nextSelected) {
        classes.push('rounded-full')
      } else {
        if (!prevSelected) classes.push('rounded-l-full')
        if (!nextSelected) classes.push('rounded-r-full')
      }
      return classes
    }
    if (isInShiftPreview(dateString)) {
      const bounds = shiftPreviewBounds.value!
      const classes = ['bg-rose-400/60', 'text-white']
      if (dateString === bounds.start) classes.push('rounded-l-full')
      if (dateString === bounds.end) classes.push('rounded-r-full')
      return classes
    }
    return ['hover:bg-white/10']
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

function handleClick(day: CalendarDay, event: MouseEvent): void {
  if (isDisabled(day.dateString)) return
  if (isMultiSelect.value && event.shiftKey && anchor.value) {
    emit('selectRange', anchor.value, day.dateString)
  } else {
    emit('select', day.dateString)
  }
  anchor.value = day.dateString
}

function handleMouseEnter(day: CalendarDay, event: MouseEvent): void {
  if (isDisabled(day.dateString)) return
  emit('hover', day.dateString)
  if (isMultiSelect.value) {
    internalHover.value = day.dateString
    internalHoverShift.value = event.shiftKey
  }
}

function handleMouseLeave(): void {
  emit('hover', null)
  internalHover.value = null
}
</script>

<template>
  <div class="w-full">
    <div v-if="!hideHeader" class="text-ink mb-4 text-center font-semibold">
      {{ monthName }} {{ year }}
    </div>

    <div
      class="text-ink-muted mb-1 grid grid-cols-7 text-center text-xs font-medium"
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
        class="focus-visible:outline-focus relative aspect-square text-sm transition-colors duration-100 focus-visible:z-10 focus-visible:outline-2 focus-visible:outline-offset-2"
        :class="[
          day.isCurrentMonth ? 'text-ink' : 'text-ink-muted',
          getDayClasses(day.dateString),
        ]"
        @click="handleClick(day, $event)"
        @mouseenter="handleMouseEnter(day, $event)"
        @mouseleave="handleMouseLeave"
      >
        {{ day.date.getDate() }}
      </button>
    </div>
  </div>
</template>
