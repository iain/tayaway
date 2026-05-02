<script setup lang="ts">
import { ref, nextTick, useTemplateRef } from 'vue'
import { storeToRefs } from 'pinia'
import { useAuthStore } from '@/stores/auth'
import { UserIcon, PhoneIcon } from '@heroicons/vue/24/outline'
import { formatBirthday } from '@/utils/date'
import BaseCard from '@/components/common/BaseCard.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'
import DefinitionRow from '@/components/common/DefinitionRow.vue'
import AppButton from '@/components/common/AppButton.vue'
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

const editField = ref<ProfileField | null>(null)
const saving = ref(false)

const editName = ref('')
const editPhone = ref('')
const editBirthday = ref('')
const editLocationName = ref('')
const editLatitude = ref<number | null>(null)
const editLongitude = ref<number | null>(null)

const editInputRef = useTemplateRef<HTMLInputElement>('editInputRef')
const editLocationRef = useTemplateRef<{ focus: () => void }>('editLocationRef')

async function openField(field: ProfileField): Promise<void> {
  editField.value = field
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
  await nextTick()
  if (field === 'address') {
    editLocationRef.value?.focus()
  } else {
    editInputRef.value?.focus()
  }
}

function cancelEdit(): void {
  editField.value = null
}

async function persist(fields: ProfileFieldValues): Promise<void> {
  saving.value = true
  try {
    await authStore.updateProfile(fields)
    editField.value = null
  } catch {
    // Error handled by mutation/toast
  } finally {
    saving.value = false
  }
}

async function saveField(): Promise<void> {
  if (saving.value) return

  switch (editField.value) {
    case 'name':
      if (!editName.value.trim()) return
      return persist({ name: editName.value.trim() })
    case 'phone':
      return persist({ phoneNumber: editPhone.value.trim() })
    case 'birthday':
      return persist({ birthday: editBirthday.value })
    case 'address':
      return persist({
        locationName: editLocationName.value.trim(),
        latitude: editLocationName.value.trim() ? editLatitude.value : null,
        longitude: editLocationName.value.trim() ? editLongitude.value : null,
      })
  }
}

async function clearPhone(): Promise<void> {
  return persist({ phoneNumber: '' })
}

async function clearBirthday(): Promise<void> {
  return persist({ birthday: '' })
}

async function clearAddress(): Promise<void> {
  return persist({ locationName: '', latitude: null, longitude: null })
}
</script>

<template>
  <div class="space-y-6">
    <BaseCard padded>
      <SectionHeading :icon="UserIcon" title="Account" />

      <dl class="divide-y divide-gray-200 dark:divide-stone-700">
        <DefinitionRow
          label="Name"
          edit-label="Edit name"
          edit-testid="edit-name-button"
          :editing="editField === 'name'"
          @edit="openField('name')"
        >
          {{ user?.name ?? 'Not set' }}
          <template #editor>
            <form class="flex items-center gap-2" @submit.prevent="saveField">
              <input
                ref="editInputRef"
                v-model="editName"
                type="text"
                aria-label="Name"
                autocomplete="name"
                placeholder="Your name"
                :maxlength="255"
                :disabled="saving"
                class="min-w-0 flex-1 rounded-md bg-gray-100 px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-rose-500 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-stone-500"
                @keyup.escape="cancelEdit"
              />
              <AppButton
                type="submit"
                size="sm"
                :disabled="!editName.trim()"
                :loading="saving"
              >
                Save
              </AppButton>
              <TextButton
                variant="secondary"
                :disabled="saving"
                @click="cancelEdit"
              >
                Cancel
              </TextButton>
            </form>
          </template>
        </DefinitionRow>
      </dl>
    </BaseCard>

    <BaseCard padded>
      <SectionHeading :icon="PhoneIcon" title="Contact Information" />

      <dl class="divide-y divide-gray-200 dark:divide-stone-700">
        <DefinitionRow
          label="Phone"
          value-class="truncate"
          edit-label="Edit phone"
          edit-testid="edit-contact-button"
          :editing="editField === 'phone'"
          @edit="openField('phone')"
        >
          {{ user?.phoneNumber || 'Not set' }}
          <template #editor>
            <div>
              <form class="flex items-center gap-2" @submit.prevent="saveField">
                <input
                  ref="editInputRef"
                  v-model="editPhone"
                  type="tel"
                  aria-label="Phone"
                  autocomplete="tel"
                  placeholder="Phone number"
                  :disabled="saving"
                  class="min-w-0 flex-1 rounded-md bg-gray-100 px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-rose-500 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-stone-500"
                  @keyup.escape="cancelEdit"
                />
                <AppButton type="submit" size="sm" :loading="saving">
                  Save
                </AppButton>
                <TextButton
                  variant="secondary"
                  :disabled="saving"
                  @click="cancelEdit"
                >
                  Cancel
                </TextButton>
              </form>
              <TextButton
                v-if="user?.phoneNumber"
                variant="danger"
                class="mt-2"
                :disabled="saving"
                @click="clearPhone"
              >
                Remove phone
              </TextButton>
            </div>
          </template>
        </DefinitionRow>

        <DefinitionRow
          label="Birthday"
          edit-label="Edit birthday"
          edit-testid="edit-birthday-button"
          :editing="editField === 'birthday'"
          @edit="openField('birthday')"
        >
          {{ user?.birthday ? formatBirthday(user.birthday) : 'Not set' }}
          <template #editor>
            <div>
              <form class="flex items-center gap-2" @submit.prevent="saveField">
                <input
                  ref="editInputRef"
                  v-model="editBirthday"
                  aria-label="Birthday"
                  type="date"
                  :disabled="saving"
                  class="min-w-0 flex-1 rounded-md bg-gray-100 px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-rose-500 dark:bg-white/5 dark:text-white dark:[color-scheme:dark] dark:outline-white/10"
                  @keyup.escape="cancelEdit"
                />
                <AppButton type="submit" size="sm" :loading="saving">
                  Save
                </AppButton>
                <TextButton
                  variant="secondary"
                  :disabled="saving"
                  @click="cancelEdit"
                >
                  Cancel
                </TextButton>
              </form>
              <TextButton
                v-if="user?.birthday"
                variant="danger"
                class="mt-2"
                :disabled="saving"
                @click="clearBirthday"
              >
                Remove birthday
              </TextButton>
            </div>
          </template>
        </DefinitionRow>

        <DefinitionRow
          label="Address"
          value-class="truncate"
          edit-label="Edit address"
          edit-testid="edit-address-button"
          :editing="editField === 'address'"
          @edit="openField('address')"
        >
          {{ user?.locationName || 'Not set' }}
          <template #editor>
            <div>
              <LocationInput
                ref="editLocationRef"
                v-model="editLocationName"
                aria-label="Address"
                :latitude="editLatitude"
                :longitude="editLongitude"
                :disabled="saving"
                @update:latitude="editLatitude = $event"
                @update:longitude="editLongitude = $event"
              />
              <div class="mt-2 flex items-center gap-2">
                <AppButton size="sm" :loading="saving" @click="saveField">
                  Save
                </AppButton>
                <TextButton
                  variant="secondary"
                  :disabled="saving"
                  @click="cancelEdit"
                >
                  Cancel
                </TextButton>
              </div>
              <TextButton
                v-if="user?.locationName"
                variant="danger"
                class="mt-2"
                :disabled="saving"
                @click="clearAddress"
              >
                Remove address
              </TextButton>
            </div>
          </template>
        </DefinitionRow>
      </dl>
    </BaseCard>
  </div>
</template>
