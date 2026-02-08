<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import DateRangeList, { type DateRangeItem } from './DateRangeList.vue'
import DateRangeModal from './DateRangeModal.vue'
import { FormInput, FormTextarea, FormActions } from '@/components/form'
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
  return name.value.trim().length > 0 && dateRanges.value.length > 0 && !props.loading
})

const showDateRangeWarning = computed(() => {
  return name.value.trim().length > 0 && dateRanges.value.length === 0
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
    class="space-y-8"
    @submit.prevent="handleSubmit"
  >
    <div class="space-y-8">
      <FormInput
        id="name"
        v-model="name"
        label="Event Name"
        placeholder="Enter event name"
        required
        :maxlength="255"
        data-testid="event-name-input"
      />

      <FormTextarea
        id="description"
        v-model="description"
        label="Description (optional)"
        placeholder="Enter event description"
        :rows="3"
        data-testid="event-description-input"
      />

      <DateRangeList
        :ranges="dateRanges"
        @add="handleAddRange"
        @remove="handleRemoveRange"
      />
      <p
        v-if="showDateRangeWarning"
        class="text-sm text-amber-600 dark:text-amber-400"
      >
        Add at least one date range to create the event.
      </p>
    </div>

    <FormActions
      :submit-label="submitLabel"
      :loading="loading"
      :disabled="!canSubmit"
      data-testid="form-actions"
      @cancel="handleCancel"
    />

    <DateRangeModal
      :open="showModal"
      :preselected-start="modalPreselectedStart"
      :preselected-end="modalPreselectedEnd"
      @save="handleModalSave"
      @close="handleModalClose"
    />
  </form>
</template>
