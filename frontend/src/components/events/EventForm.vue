<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { FormInput, FormTextarea, FormActions } from '@/components/form'

export interface EventFormData {
  name: string
  description: string
  startDate: string
  endDate: string
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

const name = ref('')
const description = ref('')
const startDate = ref('')
const endDate = ref('')

// Initialize form with initial data if provided
watch(
  () => props.initialData,
  (data) => {
    if (data) {
      name.value = data.name
      description.value = data.description
      startDate.value = data.startDate
      endDate.value = data.endDate
    }
  },
  { immediate: true }
)

const canSubmit = computed(() => {
  return name.value.trim().length > 0 && !props.loading
})

function handleSubmit(): void {
  if (!canSubmit.value) return
  emit('submit', {
    name: name.value.trim(),
    description: description.value.trim(),
    startDate: startDate.value,
    endDate: endDate.value,
  })
}

function handleCancel(): void {
  emit('cancel')
}
</script>

<template>
  <form class="space-y-8" @submit.prevent="handleSubmit">
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

      <div class="grid grid-cols-2 gap-4">
        <FormInput
          id="start-date"
          v-model="startDate"
          type="date"
          label="Start date (optional)"
          data-testid="event-start-date-input"
        />
        <FormInput
          id="end-date"
          v-model="endDate"
          type="date"
          label="End date (optional)"
          data-testid="event-end-date-input"
        />
      </div>
    </div>

    <FormActions
      :submit-label="submitLabel"
      :loading="loading"
      :disabled="!canSubmit"
      data-testid="form-actions"
      @cancel="handleCancel"
    />
  </form>
</template>
