<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import BaseModal from '@/components/common/BaseModal.vue'
import FormInput from '@/components/form/FormInput.vue'
import FormActions from '@/components/form/FormActions.vue'
import LocationInput from '@/components/form/LocationInput.vue'

export type ProfileField = 'name' | 'phone' | 'birthday' | 'address' | 'iban'

export interface ProfileFieldValues {
  name?: string
  phoneNumber?: string | null
  birthday?: string | null
  locationName?: string | null
  latitude?: number | null
  longitude?: number | null
  iban?: string | null
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
  currentIban: string | null
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
const iban = ref('')

const titles: Record<ProfileField, string> = {
  name: 'Edit Name',
  phone: 'Edit Phone',
  birthday: 'Edit Birthday',
  address: 'Edit Address',
  iban: 'Edit IBAN',
}

const title = computed(() => titles[props.field])

const canSave = computed(() => {
  if (props.field === 'name') return !!name.value.trim()
  if (props.field === 'iban') return !!iban.value.trim()
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
      iban.value = ''
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
    case 'iban':
      emit('save', { iban: iban.value.trim() })
      break
  }
}

function handleClose(): void {
  emit('close')
}
</script>

<template>
  <BaseModal :open="open" :title="title" :prevent-close="loading" @close="handleClose">
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

      <template v-else-if="field === 'iban'">
        <FormInput
          id="profile-iban"
          v-model="iban"
          label="IBAN"
          placeholder="NL00 BANK 0000 0000 00"
          autocomplete="off"
          autofocus
          :maxlength="34"
          :disabled="loading"
        />
        <p class="text-xs text-gray-500 dark:text-stone-400">
          Your IBAN is used to generate QR codes for bank transfers. It is never
          shared directly with other members.
        </p>
        <button
          v-if="currentIban"
          type="button"
          class="text-xs font-medium text-red-600 hover:text-red-500 dark:text-red-400 dark:hover:text-red-300"
          :disabled="loading"
          @click="emit('save', { iban: '' })"
        >
          Remove IBAN
        </button>
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
