<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import BaseModal from '@/components/common/BaseModal.vue'
import FormInput from '@/components/form/FormInput.vue'
import FormActions from '@/components/form/FormActions.vue'
import LocationInput from '@/components/form/LocationInput.vue'

export type ProfileField = 'name' | 'phone' | 'birthday' | 'address'

export interface ProfileFieldValues {
  name?: string
  phoneNumber?: string | null
  birthday?: string | null
  locationName?: string | null
  latitude?: number | null
  longitude?: number | null
}

const props = defineProps<{
  open: boolean
  field: ProfileField
  loading?: boolean
  currentName: string | null
  currentPhone: string | null
  currentBirthday: string | null
  currentLocationName: string | null
  currentLatitude: number | null
  currentLongitude: number | null
}>()

const emit = defineEmits<{
  close: []
  save: [fields: ProfileFieldValues]
}>()

const name = ref('')
const phone = ref('')
const birthday = ref('')
const locationName = ref('')
const latitude = ref<number | null>(null)
const longitude = ref<number | null>(null)

const titles: Record<ProfileField, string> = {
  name: 'Edit Name',
  phone: 'Edit Phone',
  birthday: 'Edit Birthday',
  address: 'Edit Address',
}

const title = computed(() => titles[props.field])

const canSave = computed(() => {
  if (props.field === 'name') return !!name.value.trim()
  return true
})

watch(
  () => props.open,
  (isOpen) => {
    if (isOpen) {
      name.value = props.currentName ?? ''
      phone.value = props.currentPhone ?? ''
      birthday.value = props.currentBirthday ?? ''
      locationName.value = props.currentLocationName ?? ''
      latitude.value = props.currentLatitude
      longitude.value = props.currentLongitude
    }
  }
)

function handleSave(): void {
  switch (props.field) {
    case 'name':
      if (name.value.trim()) {
        emit('save', { name: name.value.trim() })
      }
      break
    case 'phone':
      emit('save', { phoneNumber: phone.value.trim() || null })
      break
    case 'birthday':
      emit('save', { birthday: birthday.value || null })
      break
    case 'address':
      emit('save', {
        locationName: locationName.value.trim() || null,
        latitude: latitude.value,
        longitude: longitude.value,
      })
      break
  }
}

function handleClose(): void {
  emit('close')
}
</script>

<template>
  <BaseModal :open="open" :title="title" @close="handleClose">
    <form class="space-y-4" @submit.prevent="handleSave">
      <template v-if="field === 'name'">
        <FormInput
          id="profile-name"
          v-model="name"
          label="Name"
          placeholder="Enter your name"
          autocomplete="name"
          autofocus
          required
          :maxlength="255"
          :disabled="loading"
        />
      </template>

      <template v-else-if="field === 'phone'">
        <FormInput
          id="profile-phone"
          v-model="phone"
          label="Phone"
          type="tel"
          placeholder="Enter your phone number"
          autocomplete="tel"
          autofocus
          :disabled="loading"
        />
      </template>

      <template v-else-if="field === 'birthday'">
        <FormInput
          id="profile-birthday"
          v-model="birthday"
          label="Birthday"
          type="date"
          autofocus
          :disabled="loading"
        />
      </template>

      <template v-else-if="field === 'address'">
        <LocationInput
          v-model="locationName"
          :latitude="latitude"
          :longitude="longitude"
          :disabled="loading"
          label="Address"
          @update:latitude="latitude = $event"
          @update:longitude="longitude = $event"
        />
      </template>

      <FormActions
        submit-label="Save"
        :loading="loading"
        :disabled="!canSave"
        @cancel="handleClose"
      />
    </form>
  </BaseModal>
</template>
