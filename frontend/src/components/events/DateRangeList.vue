<script setup lang="ts">
import { computed } from 'vue'
import { PlusIcon, TrashIcon } from '@heroicons/vue/24/outline'
import IconButton from '@/components/common/IconButton.vue'
import TextButton from '@/components/common/TextButton.vue'
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
  return [...props.ranges].sort((a, b) =>
    a.start_date.localeCompare(b.start_date)
  )
})

function handleAdd(): void {
  emit('add')
}

function handleRemove(index: number): void {
  // Find the original index in props.ranges
  const sortedRange = sortedRanges.value[index]!
  const originalIndex = props.ranges.findIndex(
    (r) =>
      r.start_date === sortedRange.start_date &&
      r.end_date === sortedRange.end_date
  )
  emit('remove', originalIndex)
}
</script>

<template>
  <div>
    <div class="mb-3 flex items-center justify-between">
      <label class="block text-sm/6 font-medium text-ink">Date Ranges</label>
      <TextButton data-testid="add-date-range-button" @click="handleAdd">
        <PlusIcon class="size-4" />
        Add Range
      </TextButton>
    </div>

    <div v-if="sortedRanges.length === 0" class="text-sm text-ink-muted italic">
      No date ranges added yet. Click "Add Range" to add potential dates.
    </div>

    <ul v-else class="space-y-2">
      <li
        v-for="(range, index) in sortedRanges"
        :key="`${range.start_date}-${range.end_date}`"
        class="flex items-center justify-between rounded-md bg-gray-50 px-3 py-2 dark:bg-white/5"
      >
        <span class="text-sm text-ink">
          {{ formatDateDisplay(range.start_date) }} -
          {{ formatDateDisplay(range.end_date) }}
        </span>
        <IconButton
          variant="danger"
          label="Remove"
          @click="handleRemove(index)"
        >
          <TrashIcon class="size-4" />
        </IconButton>
      </li>
    </ul>
  </div>
</template>
