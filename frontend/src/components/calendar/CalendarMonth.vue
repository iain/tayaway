<script setup lang="ts">
import { computed } from 'vue'
import { useCalendar, type CalendarDay } from '@/composables/useCalendar'

const props = defineProps<{
  year: number
  month: number
  selectedStart: string | null
  selectedEnd: string | null
  hoverDate: string | null
}>()

const emit = defineEmits<{
  select: [date: string]
  hover: [date: string | null]
}>()

const { getDaysInMonth, getMonthName, isDateInRange, isDateInHoverRange } = useCalendar()

const days = computed<CalendarDay[]>(() => getDaysInMonth(props.year, props.month))

const monthName = computed(() => getMonthName(props.month))

const weekDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']

function isSelected(dateString: string): boolean {
  return dateString === props.selectedStart || dateString === props.selectedEnd
}

function isInRange(dateString: string): boolean {
  return isDateInRange(dateString, props.selectedStart, props.selectedEnd)
}

function isInHoverRange(dateString: string): boolean {
  // Only show hover range when we have a start but no end yet
  if (props.selectedEnd || !props.selectedStart) return false
  return isDateInHoverRange(dateString, props.selectedStart, props.hoverDate)
}

function handleClick(day: CalendarDay): void {
  emit('select', day.dateString)
}

function handleMouseEnter(day: CalendarDay): void {
  emit('hover', day.dateString)
}

function handleMouseLeave(): void {
  emit('hover', null)
}
</script>

<template>
  <div class="w-full">
    <div class="text-center font-semibold text-gray-900 dark:text-white mb-4">
      {{ monthName }} {{ year }}
    </div>

    <div class="grid grid-cols-7 gap-px text-center text-xs font-medium text-gray-500 dark:text-gray-400 mb-2">
      <div
        v-for="day in weekDays"
        :key="day"
        class="py-2"
      >
        {{ day }}
      </div>
    </div>

    <div class="grid grid-cols-7 gap-px">
      <button
        v-for="day in days"
        :key="day.dateString"
        :data-testid="`calendar-day-${day.dateString}`"
        type="button"
        class="relative py-2 text-sm focus:z-10 focus:outline-none focus:ring-2 focus:ring-indigo-500"
        :class="[
          day.isCurrentMonth
            ? 'text-gray-900 dark:text-gray-100'
            : 'text-gray-400 dark:text-gray-600',
          isSelected(day.dateString)
            ? 'bg-indigo-600 text-white font-semibold'
            : isInRange(day.dateString)
              ? 'bg-indigo-100 dark:bg-indigo-900/50'
              : isInHoverRange(day.dateString)
                ? 'bg-indigo-50 dark:bg-indigo-900/30'
                : 'hover:bg-gray-100 dark:hover:bg-gray-700',
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
