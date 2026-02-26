<script setup lang="ts">
import { ref, watch } from 'vue'
import BaseModal from '@/components/common/BaseModal.vue'
import FormInput from '@/components/form/FormInput.vue'
import FormActions from '@/components/form/FormActions.vue'
import LocationInput from '@/components/form/LocationInput.vue'

const props = defineProps<{
  open: boolean
  loading?: boolean
  currentPhone: string | null
  currentBirthday: string | null
  currentLocationName: string | null
  currentLatitude: number | null
  currentLongitude: number | null
}>()

const emit = defineEmits<{
  close: []
  save: [
    fields: {
      phoneNumber: string | null
      birthday: string | null
      locationName: string | null
      latitude: number | null
      longitude: number | null
    },
  ]
}>()

const phone = ref('')
const birthday = ref('')
const locationName = ref('')
const latitude = ref<number | null>(null)
const longitude = ref<number | null>(null)

watch(
  () => props.open,
  (isOpen) => {
    if (isOpen) {
      phone.value = props.currentPhone ?? ''
      birthday.value = props.currentBirthday ?? ''
      locationName.value = props.currentLocationName ?? ''
      latitude.value = props.currentLatitude
      longitude.value = props.currentLongitude
    }
  }
)

function handleSave(): void {
  emit('save', {
    phoneNumber: phone.value.trim() || null,
    birthday: birthday.value || null,
    locationName: locationName.value.trim() || null,
    latitude: latitude.value,
    longitude: longitude.value,
  })
}

function handleClose(): void {
  emit('close')
}
</script>

<template>
  <BaseModal :open="open" title="Edit Contact Info" @close="handleClose">
    <form class="space-y-4" @submit.prevent="handleSave">
      <FormInput
        id="profile-phone"
        v-model="phone"
        label="Phone"
        type="tel"
        placeholder="Enter your phone number"
        autocomplete="tel"
        :disabled="loading"
      />

      <FormInput
        id="profile-birthday"
        v-model="birthday"
        label="Birthday"
        type="date"
        :disabled="loading"
      />

      <LocationInput
        v-model="locationName"
        :latitude="latitude"
        :longitude="longitude"
        :disabled="loading"
        label="Address"
        @update:latitude="latitude = $event"
        @update:longitude="longitude = $event"
      />

      <FormActions
        submit-label="Save"
        :loading="loading"
        @cancel="handleClose"
      />
    </form>
  </BaseModal>
</template>
