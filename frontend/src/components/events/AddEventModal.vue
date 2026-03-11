<script setup lang="ts">
import { ref, watch } from 'vue'
import BaseModal from '@/components/common/BaseModal.vue'
import FormInput from '@/components/form/FormInput.vue'
import FormTextarea from '@/components/form/FormTextarea.vue'
import FormActions from '@/components/form/FormActions.vue'
import LocationInput from '@/components/form/LocationInput.vue'

const props = defineProps<{
  open: boolean
  loading?: boolean
}>()

const emit = defineEmits<{
  close: []
  save: [
    name: string,
    description: string,
    startDate: string | undefined,
    endDate: string | undefined,
    locationName: string | undefined,
    latitude: number | undefined,
    longitude: number | undefined,
  ]
}>()

const name = ref('')
const description = ref('')
const setDates = ref(false)
const startDate = ref('')
const endDate = ref('')
const locationName = ref('')
const latitude = ref<number | null>(null)
const longitude = ref<number | null>(null)

watch(
  () => props.open,
  (isOpen) => {
    if (isOpen) {
      name.value = ''
      description.value = ''
      setDates.value = false
      startDate.value = ''
      endDate.value = ''
      locationName.value = ''
      latitude.value = null
      longitude.value = null
    }
  }
)

function handleSave(): void {
  if (name.value.trim()) {
    emit(
      'save',
      name.value.trim(),
      description.value.trim(),
      setDates.value && startDate.value ? startDate.value : undefined,
      setDates.value && endDate.value ? endDate.value : undefined,
      locationName.value || undefined,
      latitude.value ?? undefined,
      longitude.value ?? undefined
    )
  }
}

function handleClose(): void {
  emit('close')
}
</script>

<template>
  <BaseModal :open="open" title="New Event" :prevent-close="loading" @close="handleClose">
    <form class="space-y-4" @submit.prevent="handleSave">
      <FormInput
        id="event-name"
        v-model="name"
        label="Name"
        placeholder="Enter event name"
        autocomplete="off"
        autofocus
        required
        :maxlength="255"
        :disabled="loading"
      />
      <FormTextarea
        id="event-description"
        v-model="description"
        label="Description (optional)"
        placeholder="Enter event description"
        :rows="3"
        :disabled="loading"
      />

      <LocationInput
        v-model="locationName"
        v-model:latitude="latitude"
        v-model:longitude="longitude"
        label="Location (optional)"
        :disabled="loading"
      />

      <div class="flex items-center gap-2">
        <input
          id="set-dates"
          v-model="setDates"
          type="checkbox"
          class="size-4 rounded border-gray-300 text-rose-600 focus:ring-rose-500 dark:border-stone-600 dark:bg-stone-700"
          :disabled="loading"
        />
        <label
          for="set-dates"
          class="text-sm font-medium text-gray-700 dark:text-stone-300"
          >Set dates</label
        >
      </div>

      <div v-if="setDates" class="grid grid-cols-2 gap-4">
        <FormInput
          id="event-start-date"
          v-model="startDate"
          type="date"
          label="Start date"
          required
          :disabled="loading"
        />
        <FormInput
          id="event-end-date"
          v-model="endDate"
          type="date"
          label="End date"
          required
          :disabled="loading"
        />
      </div>

      <FormActions
        submit-label="Create Event"
        loading-label="Creating..."
        submit-testid="modal-save-button"
        :loading="loading"
        :disabled="!name.trim()"
        @cancel="handleClose"
      />
    </form>
  </BaseModal>
</template>
