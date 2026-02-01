<script setup lang="ts">
import { computed } from 'vue'
import { PlusIcon, TrashIcon } from '@heroicons/vue/24/outline'
import { useCalendar } from '@/composables/useCalendar'

export interface DateRangeItem {
  start_date: string
  end_date: string
}

const props = defineProps<{
  ranges: DateRangeItem[]
}>()

const emit = defineEmits<{
  add: []
  remove: [index: number]
}>()

const { formatDateDisplay } = useCalendar()

// Sort ranges by start_date for display
const sortedRanges = computed(() => {
  return [...props.ranges].sort((a, b) => a.start_date.localeCompare(b.start_date))
})

function handleAdd(): void {
  emit('add')
}

function handleRemove(index: number): void {
  // Find the original index in props.ranges
  const sortedRange = sortedRanges.value[index]
  const originalIndex = props.ranges.findIndex(
    r => r.start_date === sortedRange.start_date && r.end_date === sortedRange.end_date
  )
  emit('remove', originalIndex)
}
</script>

<template>
  <div>
    <div class="flex items-center justify-between mb-3">
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300">
        Date Ranges
      </label>
      <button
        type="button"
        data-testid="add-date-range-button"
        class="inline-flex items-center gap-1 text-sm text-indigo-600 dark:text-indigo-400 hover:text-indigo-500"
        @click="handleAdd"
      >
        <PlusIcon class="size-4" />
        Add Range
      </button>
    </div>

    <div
      v-if="sortedRanges.length === 0"
      class="text-sm text-gray-500 dark:text-gray-400 italic"
    >
      No date ranges added yet. Click "Add Range" to add potential dates.
    </div>

    <ul
      v-else
      class="space-y-2"
    >
      <li
        v-for="(range, index) in sortedRanges"
        :key="`${range.start_date}-${range.end_date}`"
        class="flex items-center justify-between bg-gray-50 dark:bg-gray-700/50 rounded-md px-3 py-2"
      >
        <span class="text-sm text-gray-900 dark:text-gray-100">
          {{ formatDateDisplay(range.start_date) }} - {{ formatDateDisplay(range.end_date) }}
        </span>
        <button
          type="button"
          class="text-gray-400 hover:text-red-500 dark:hover:text-red-400"
          @click="handleRemove(index)"
        >
          <TrashIcon class="size-4" />
          <span class="sr-only">Remove</span>
        </button>
      </li>
    </ul>
  </div>
</template>
