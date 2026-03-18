<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { FormInput, FormTextarea, FormActions } from '@/components/form'
import LocationInput from '@/components/form/LocationInput.vue'

export interface EventFormData {
  name: string
  description: string
  startDate: string
  endDate: string
  locationName: string
  latitude: number | null
  longitude: number | null
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
const locationName = ref('')
const latitude = ref<number | null>(null)
const longitude = ref<number | null>(null)

// Initialize form with initial data if provided
watch(
  () => props.initialData,
  (data) => {
    if (data) {
      name.value = data.name
      description.value = data.description
      startDate.value = data.startDate
      endDate.value = data.endDate
      locationName.value = data.locationName
      latitude.value = data.latitude
      longitude.value = data.longitude
    }
  },
  { immediate: true }
)

const dateError = computed(() => {
  if (startDate.value && endDate.value && endDate.value < startDate.value) {
    return 'End date must be on or after start date'
  }
  return null
})

const canSubmit = computed(() => {
  return name.value.trim().length > 0 && !dateError.value && !props.loading
})

function handleSubmit(): void {
  if (!canSubmit.value) return
  emit('submit', {
    name: name.value.trim(),
    description: description.value.trim(),
    startDate: startDate.value,
    endDate: endDate.value,
    locationName: locationName.value,
    latitude: latitude.value,
    longitude: longitude.value,
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

      <LocationInput
        v-model="locationName"
        v-model:latitude="latitude"
        v-model:longitude="longitude"
        label="Location (optional)"
      />

      <div>
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
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
        <p
          v-if="dateError"
          class="mt-1.5 text-sm text-red-600 dark:text-red-400"
        >
          {{ dateError }}
        </p>
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
