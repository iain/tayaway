<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import DateRangeList, { type DateRangeItem } from './DateRangeList.vue'
import DateRangeModal from './DateRangeModal.vue'
import { useCalendar } from '@/composables/useCalendar'

export interface EventFormData {
  name: string
  description: string
  date_ranges: DateRangeItem[]
}

const props = defineProps<{
  initialData?: EventFormData
  submitLabel?: string
  loading?: boolean
}>()

const emit = defineEmits<{
  submit: [data: EventFormData]
  cancel: []
}>()

const { getNextMonday, addDays } = useCalendar()

const name = ref('')
const description = ref('')
const dateRanges = ref<DateRangeItem[]>([])
const showModal = ref(false)
const modalPreselectedStart = ref<string | null>(null)
const modalPreselectedEnd = ref<string | null>(null)

// Initialize form with initial data if provided
watch(() => props.initialData, (data) => {
  if (data) {
    name.value = data.name
    description.value = data.description
    dateRanges.value = [...data.date_ranges]
  }
}, { immediate: true })

const canSubmit = computed(() => {
  return name.value.trim().length > 0 && !props.loading
})

function handleAddRange(): void {
  // Smart preselection: if we have existing ranges, preselect next week after latest end date
  if (dateRanges.value.length > 0) {
    const latestEndDate = dateRanges.value
      .map(r => r.end_date)
      .sort()
      .pop()!
    const nextMonday = getNextMonday(latestEndDate)
    const nextSunday = addDays(nextMonday, 6)
    modalPreselectedStart.value = nextMonday
    modalPreselectedEnd.value = nextSunday
  } else {
    modalPreselectedStart.value = null
    modalPreselectedEnd.value = null
  }
  showModal.value = true
}

function handleModalSave(start: string, end: string): void {
  dateRanges.value = [...dateRanges.value, { start_date: start, end_date: end }]
  showModal.value = false
}

function handleModalClose(): void {
  showModal.value = false
}

function handleRemoveRange(index: number): void {
  dateRanges.value = dateRanges.value.filter((_, i) => i !== index)
}

function handleSubmit(): void {
  if (!canSubmit.value) return
  emit('submit', {
    name: name.value.trim(),
    description: description.value.trim(),
    date_ranges: dateRanges.value,
  })
}

function handleCancel(): void {
  emit('cancel')
}
</script>

<template>
  <form
    class="space-y-6"
    @submit.prevent="handleSubmit"
  >
    <div>
      <label
        for="name"
        class="block text-sm font-medium text-gray-700 dark:text-gray-300"
      >
        Event Name
      </label>
      <input
        id="name"
        v-model="name"
        type="text"
        required
        maxlength="255"
        class="mt-1 block w-full rounded-md border-gray-300 dark:border-gray-600 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm dark:bg-gray-700 dark:text-white"
        placeholder="Enter event name"
      >
    </div>

    <div>
      <label
        for="description"
        class="block text-sm font-medium text-gray-700 dark:text-gray-300"
      >
        Description (optional)
      </label>
      <textarea
        id="description"
        v-model="description"
        rows="3"
        class="mt-1 block w-full rounded-md border-gray-300 dark:border-gray-600 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm dark:bg-gray-700 dark:text-white"
        placeholder="Enter event description"
      />
    </div>

    <DateRangeList
      :ranges="dateRanges"
      @add="handleAddRange"
      @remove="handleRemoveRange"
    />

    <div class="flex justify-end gap-3 pt-4">
      <button
        type="button"
        class="rounded-md bg-white dark:bg-gray-700 px-3 py-2 text-sm font-semibold text-gray-900 dark:text-white shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-gray-600 hover:bg-gray-50 dark:hover:bg-gray-600"
        @click="handleCancel"
      >
        Cancel
      </button>
      <button
        type="submit"
        :disabled="!canSubmit"
        class="rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed"
      >
        {{ loading ? 'Saving...' : (submitLabel || 'Save') }}
      </button>
    </div>

    <DateRangeModal
      :open="showModal"
      :preselected-start="modalPreselectedStart"
      :preselected-end="modalPreselectedEnd"
      @save="handleModalSave"
      @close="handleModalClose"
    />
  </form>
</template>
