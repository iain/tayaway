<script setup lang="ts">
import { ref, computed, nextTick } from 'vue'
import { storeToRefs } from 'pinia'
import { useAuthStore } from '@/stores/auth'
import { UserIcon, PhoneIcon, BanknotesIcon } from '@heroicons/vue/24/outline'
import { formatBirthday } from '@/utils/date'
import PageHeader from '@/components/common/PageHeader.vue'
import BaseCard from '@/components/common/BaseCard.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'
import DefinitionRow from '@/components/common/DefinitionRow.vue'
import AppButton from '@/components/common/AppButton.vue'
import TextButton from '@/components/common/TextButton.vue'
import LocationInput from '@/components/form/LocationInput.vue'

type ProfileField = 'name' | 'phone' | 'birthday' | 'address' | 'iban'

interface ProfileFieldValues {
  name?: string
  phoneNumber?: string | null
  birthday?: string | null
  locationName?: string | null
  latitude?: number | null
  longitude?: number | null
  iban?: string | null
}

const authStore = useAuthStore()
const { user } = storeToRefs(authStore)

const editField = ref<ProfileField | null>(null)
const saving = ref(false)

// Edit state per field
const editName = ref('')
const editPhone = ref('')
const editBirthday = ref('')
const editLocationName = ref('')
const editLatitude = ref<number | null>(null)
const editLongitude = ref<number | null>(null)
const editIban = ref('')

const editInputRef = ref<HTMLInputElement | null>(null)

const initials = computed(() => {
  const name = user.value?.name
  if (name) {
    const parts = name.trim().split(/\s+/)
    if (parts.length >= 2) {
      const first = parts[0]?.[0] ?? ''
      const last = parts[parts.length - 1]?.[0] ?? ''
      return (first + last).toUpperCase()
    }
    return (parts[0]?.[0] ?? '').toUpperCase()
  }
  return user.value?.email?.[0]?.toUpperCase() ?? '?'
})

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
    case 'iban':
      editIban.value = ''
      break
  }
  await nextTick()
  editInputRef.value?.focus()
}

function cancelEdit(): void {
  editField.value = null
}

async function saveField(): Promise<void> {
  if (saving.value) return
  const fields: ProfileFieldValues = {}

  switch (editField.value) {
    case 'name':
      if (!editName.value.trim()) return
      fields.name = editName.value.trim()
      break
    case 'phone':
      fields.phoneNumber = editPhone.value.trim() || null
      break
    case 'birthday':
      fields.birthday = editBirthday.value || null
      break
    case 'address':
      fields.locationName = editLocationName.value.trim() || null
      fields.latitude = editLatitude.value
      fields.longitude = editLongitude.value
      break
    case 'iban':
      fields.iban = editIban.value.trim()
      break
    default:
      return
  }

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

async function removeIban(): Promise<void> {
  saving.value = true
  try {
    await authStore.updateProfile({ iban: '' })
    editField.value = null
  } catch {
    // Error handled by mutation/toast
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div>
    <PageHeader title="Profile" />

    <!-- User Identity Header -->
    <div class="mb-6 flex items-center gap-4">
      <div
        class="flex size-16 shrink-0 items-center justify-center rounded-full bg-rose-100 text-xl font-semibold text-rose-600 dark:bg-rose-900/30 dark:text-rose-400"
      >
        {{ initials }}
      </div>
      <div class="min-w-0">
        <p class="truncate text-lg font-semibold text-gray-900 dark:text-white">
          {{ user?.name ?? 'No name set' }}
        </p>
        <p class="truncate text-sm text-gray-500 dark:text-stone-400">
          {{ user?.email }}
        </p>
      </div>
    </div>

    <!-- Account Section -->
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

    <!-- Contact Information Section -->
    <BaseCard padded class="mt-6">
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
          {{ user?.phoneNumber ?? 'Not set' }}
          <template #editor>
            <form class="flex items-center gap-2" @submit.prevent="saveField">
              <input
                ref="editInputRef"
                v-model="editPhone"
                type="tel"
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
            <form class="flex items-center gap-2" @submit.prevent="saveField">
              <input
                ref="editInputRef"
                v-model="editBirthday"
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
          {{ user?.locationName ?? 'Not set' }}
          <template #editor>
            <div>
              <LocationInput
                v-model="editLocationName"
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
            </div>
          </template>
        </DefinitionRow>
      </dl>
    </BaseCard>

    <!-- Payment Section -->
    <BaseCard padded class="mt-6">
      <SectionHeading :icon="BanknotesIcon" title="Payment" />

      <p class="mb-2 text-sm text-gray-500 dark:text-stone-400">
        Adding your IBAN lets others pay you with a single QR code scan when
        settling shared expenses. Your IBAN is stored securely and never shared
        with other members &mdash; it is only used server-side to generate
        payment QR codes.
      </p>

      <dl class="divide-y divide-gray-200 dark:divide-stone-700">
        <DefinitionRow
          label="IBAN"
          value-class="truncate font-mono"
          edit-label="Edit IBAN"
          edit-testid="edit-iban-button"
          :editing="editField === 'iban'"
          @edit="openField('iban')"
        >
          {{ user?.iban ?? 'Not set' }}
          <template #editor>
            <div>
              <form class="flex items-center gap-2" @submit.prevent="saveField">
                <input
                  ref="editInputRef"
                  v-model="editIban"
                  type="text"
                  autocomplete="off"
                  placeholder="NL00 BANK 0000 0000 00"
                  :maxlength="34"
                  :disabled="saving"
                  class="min-w-0 flex-1 rounded-md bg-gray-100 px-3 py-1.5 font-mono text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:font-mono placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-rose-500 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-stone-500"
                  @keyup.escape="cancelEdit"
                />
                <AppButton
                  type="submit"
                  size="sm"
                  :disabled="!editIban.trim()"
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
              <TextButton
                v-if="user?.iban"
                variant="danger"
                class="mt-2"
                :disabled="saving"
                @click="removeIban"
              >
                Remove IBAN
              </TextButton>
            </div>
          </template>
        </DefinitionRow>
      </dl>
    </BaseCard>
  </div>
</template>
