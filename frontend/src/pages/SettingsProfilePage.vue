<script setup lang="ts">
import { ref, nextTick, useTemplateRef } from 'vue'
import { storeToRefs } from 'pinia'
import { useAuthStore } from '@/stores/auth'
import { UserIcon, XCircleIcon } from '@heroicons/vue/24/outline'
import { formatBirthday } from '@/utils/date'
import BaseCard from '@/components/common/BaseCard.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'
import DefinitionRow from '@/components/common/DefinitionRow.vue'
import AppButton from '@/components/common/AppButton.vue'
import IconButton from '@/components/common/IconButton.vue'
import TextButton from '@/components/common/TextButton.vue'
import LocationInput from '@/components/form/LocationInput.vue'

type ProfileField = 'name' | 'phone' | 'birthday' | 'address'

interface ProfileFieldValues {
  name?: string
  phoneNumber?: string
  birthday?: string
  locationName?: string
  latitude?: number | null
  longitude?: number | null
}

const authStore = useAuthStore()
const { user } = storeToRefs(authStore)

// Per-field edit state. Multiple editors can be open at once — opening a new
// one never silently discards another. The user got each form there by an
// explicit click, so they own the visual density that follows.
const editingFields = ref(new Set<ProfileField>())
const savingFields = ref(new Set<ProfileField>())
const saveErrors = ref(new Map<ProfileField, string>())

const editName = ref('')
const editPhone = ref('')
const editBirthday = ref('')
const editLocationName = ref('')
const editLatitude = ref<number | null>(null)
const editLongitude = ref<number | null>(null)

const nameInputRef = useTemplateRef<HTMLInputElement>('nameInputRef')
const phoneInputRef = useTemplateRef<HTMLInputElement>('phoneInputRef')
const birthdayInputRef = useTemplateRef<HTMLInputElement>('birthdayInputRef')
const locationRef = useTemplateRef<{ focus: () => void }>('locationRef')

async function openField(field: ProfileField): Promise<void> {
  if (editingFields.value.has(field)) return
  saveErrors.value.delete(field)
  switch (field) {
    case 'name':
      editName.value = user.value?.name ?? ''
      break
    case 'phone':
      editPhone.value = user.value?.phoneNumber ?? ''
      break
    case 'birthday':
      editBirthday.value = user.value?.birthday ?? ''
      break
    case 'address':
      editLocationName.value = user.value?.locationName ?? ''
      editLatitude.value = user.value?.latitude ?? null
      editLongitude.value = user.value?.longitude ?? null
      break
  }
  editingFields.value.add(field)
  await nextTick()
  switch (field) {
    case 'name':
      nameInputRef.value?.focus()
      break
    case 'phone':
      phoneInputRef.value?.focus()
      break
    case 'birthday':
      birthdayInputRef.value?.focus()
      break
    case 'address':
      locationRef.value?.focus()
      break
  }
}

function cancelEdit(field: ProfileField): void {
  editingFields.value.delete(field)
  saveErrors.value.delete(field)
}

async function persist(
  field: ProfileField,
  payload: ProfileFieldValues
): Promise<void> {
  if (savingFields.value.has(field)) return
  savingFields.value.add(field)
  saveErrors.value.delete(field)
  try {
    await authStore.updateProfile(payload)
    editingFields.value.delete(field)
  } catch {
    // The toast covers this for sighted users; the inline message is here so
    // users who dismissed the toast (or never saw it) still get a clear signal
    // that the save didn't land.
    saveErrors.value.set(field, "Couldn't save — try again.")
  } finally {
    savingFields.value.delete(field)
  }
}

async function saveField(field: ProfileField): Promise<void> {
  switch (field) {
    case 'name':
      if (!editName.value.trim()) return
      return persist(field, { name: editName.value.trim() })
    case 'phone':
      return persist(field, { phoneNumber: editPhone.value.trim() })
    case 'birthday':
      return persist(field, { birthday: editBirthday.value })
    case 'address':
      return persist(field, {
        locationName: editLocationName.value.trim(),
        latitude: editLocationName.value.trim() ? editLatitude.value : null,
        longitude: editLocationName.value.trim() ? editLongitude.value : null,
      })
  }
}

async function clearPhone(): Promise<void> {
  return persist('phone', { phoneNumber: '' })
}

async function clearBirthday(): Promise<void> {
  return persist('birthday', { birthday: '' })
}

async function clearAddress(): Promise<void> {
  return persist('address', {
    locationName: '',
    latitude: null,
    longitude: null,
  })
}
</script>

<template>
  <div>
    <BaseCard padded>
      <SectionHeading :icon="UserIcon" title="About you" />

      <dl class="divide-y divide-gray-200 dark:divide-stone-700">
        <DefinitionRow
          label="Name"
          edit-label="Edit name"
          edit-testid="edit-name-button"
          :editing="editingFields.has('name')"
          @edit="openField('name')"
        >
          {{ user?.name ?? 'Not set' }}
          <template #editor>
            <div>
              <form
                class="flex flex-wrap items-center gap-2"
                :aria-busy="savingFields.has('name')"
                @submit.prevent="saveField('name')"
              >
                <input
                  ref="nameInputRef"
                  v-model="editName"
                  type="text"
                  aria-label="Name"
                  autocomplete="name"
                  placeholder="Your name"
                  :maxlength="255"
                  :disabled="savingFields.has('name')"
                  class="min-w-0 flex-1 rounded-md bg-gray-100 px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-rose-500 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-stone-500"
                  @keyup.escape="cancelEdit('name')"
                />
                <AppButton
                  type="submit"
                  size="sm"
                  :disabled="!editName.trim()"
                  :loading="savingFields.has('name')"
                >
                  Save
                </AppButton>
                <TextButton
                  variant="secondary"
                  :disabled="savingFields.has('name')"
                  @click="cancelEdit('name')"
                >
                  Cancel
                </TextButton>
              </form>
              <p
                v-if="saveErrors.get('name')"
                role="alert"
                class="mt-1 text-sm text-red-600 dark:text-red-400"
              >
                {{ saveErrors.get('name') }}
              </p>
            </div>
          </template>
        </DefinitionRow>
        <DefinitionRow
          label="Phone"
          value-class="truncate"
          edit-label="Edit phone"
          edit-testid="edit-contact-button"
          :editing="editingFields.has('phone')"
          @edit="openField('phone')"
        >
          {{ user?.phoneNumber || 'Not set' }}
          <template #editor>
            <div>
              <form
                class="flex flex-wrap items-center gap-2"
                :aria-busy="savingFields.has('phone')"
                @submit.prevent="saveField('phone')"
              >
                <input
                  ref="phoneInputRef"
                  v-model="editPhone"
                  type="tel"
                  aria-label="Phone"
                  autocomplete="tel"
                  placeholder="Phone number"
                  :disabled="savingFields.has('phone')"
                  class="min-w-0 flex-1 rounded-md bg-gray-100 px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-rose-500 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-stone-500"
                  @keyup.escape="cancelEdit('phone')"
                />
                <AppButton
                  type="submit"
                  size="sm"
                  :loading="savingFields.has('phone')"
                >
                  Save
                </AppButton>
                <TextButton
                  variant="secondary"
                  :disabled="savingFields.has('phone')"
                  @click="cancelEdit('phone')"
                >
                  Cancel
                </TextButton>
                <IconButton
                  v-if="user?.phoneNumber"
                  variant="danger"
                  label="Remove phone"
                  :disabled="savingFields.has('phone')"
                  @click="clearPhone"
                >
                  <XCircleIcon class="size-5" />
                </IconButton>
              </form>
              <p
                v-if="saveErrors.get('phone')"
                role="alert"
                class="mt-1 text-sm text-red-600 dark:text-red-400"
              >
                {{ saveErrors.get('phone') }}
              </p>
            </div>
          </template>
        </DefinitionRow>

        <DefinitionRow
          label="Birthday"
          edit-label="Edit birthday"
          edit-testid="edit-birthday-button"
          :editing="editingFields.has('birthday')"
          @edit="openField('birthday')"
        >
          {{ user?.birthday ? formatBirthday(user.birthday) : 'Not set' }}
          <template #editor>
            <div>
              <form
                class="flex flex-wrap items-center gap-2"
                :aria-busy="savingFields.has('birthday')"
                @submit.prevent="saveField('birthday')"
              >
                <input
                  ref="birthdayInputRef"
                  v-model="editBirthday"
                  aria-label="Birthday"
                  type="date"
                  :disabled="savingFields.has('birthday')"
                  class="min-w-0 flex-1 rounded-md bg-gray-100 px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-rose-500 dark:bg-white/5 dark:text-white dark:[color-scheme:dark] dark:outline-white/10"
                  @keyup.escape="cancelEdit('birthday')"
                />
                <AppButton
                  type="submit"
                  size="sm"
                  :loading="savingFields.has('birthday')"
                >
                  Save
                </AppButton>
                <TextButton
                  variant="secondary"
                  :disabled="savingFields.has('birthday')"
                  @click="cancelEdit('birthday')"
                >
                  Cancel
                </TextButton>
                <IconButton
                  v-if="user?.birthday"
                  variant="danger"
                  label="Remove birthday"
                  :disabled="savingFields.has('birthday')"
                  @click="clearBirthday"
                >
                  <XCircleIcon class="size-5" />
                </IconButton>
              </form>
              <p
                v-if="saveErrors.get('birthday')"
                role="alert"
                class="mt-1 text-sm text-red-600 dark:text-red-400"
              >
                {{ saveErrors.get('birthday') }}
              </p>
            </div>
          </template>
        </DefinitionRow>

        <DefinitionRow
          label="Address"
          value-class="truncate"
          edit-label="Edit address"
          edit-testid="edit-address-button"
          :editing="editingFields.has('address')"
          @edit="openField('address')"
        >
          {{ user?.locationName || 'Not set' }}
          <template #editor>
            <div :aria-busy="savingFields.has('address')">
              <LocationInput
                ref="locationRef"
                v-model="editLocationName"
                aria-label="Address"
                :latitude="editLatitude"
                :longitude="editLongitude"
                :disabled="savingFields.has('address')"
                @update:latitude="editLatitude = $event"
                @update:longitude="editLongitude = $event"
              />
              <div class="mt-2 flex flex-wrap items-center gap-2">
                <AppButton
                  size="sm"
                  :loading="savingFields.has('address')"
                  @click="saveField('address')"
                >
                  Save
                </AppButton>
                <TextButton
                  variant="secondary"
                  :disabled="savingFields.has('address')"
                  @click="cancelEdit('address')"
                >
                  Cancel
                </TextButton>
                <IconButton
                  v-if="user?.locationName"
                  variant="danger"
                  label="Remove address"
                  :disabled="savingFields.has('address')"
                  @click="clearAddress"
                >
                  <XCircleIcon class="size-5" />
                </IconButton>
              </div>
              <p
                v-if="saveErrors.get('address')"
                role="alert"
                class="mt-1 text-sm text-red-600 dark:text-red-400"
              >
                {{ saveErrors.get('address') }}
              </p>
            </div>
          </template>
        </DefinitionRow>
      </dl>
    </BaseCard>
  </div>
</template>
