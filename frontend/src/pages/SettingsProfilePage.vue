<script setup lang="ts">
import { computed, ref, nextTick, useTemplateRef } from 'vue'
import { storeToRefs } from 'pinia'
import { useAuthStore } from '@/stores/auth'
import { UserIcon, XCircleIcon } from '@heroicons/vue/24/outline'
import { formatBirthday, localIsoDate } from '@/utils/date'
import BaseCard from '@/components/common/BaseCard.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'
import DefinitionRow from '@/components/common/DefinitionRow.vue'
import AppButton from '@/components/common/AppButton.vue'
import IconButton from '@/components/common/IconButton.vue'
import TextButton from '@/components/common/TextButton.vue'
import LocationInput from '@/components/form/LocationInput.vue'
import TimezoneSelect from '@/components/form/TimezoneSelect.vue'
import { deviceTimezone } from '@/utils/timezone'
import { TEXT_LIMITS } from '@/constants/limits'

type ProfileField = 'name' | 'phone' | 'birthday' | 'address' | 'timezone'

interface ProfileFieldValues {
  name?: string
  phoneNumber?: string
  birthday?: string
  locationName?: string
  latitude?: number | null
  longitude?: number | null
  timezone?: string | null
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
// "" = follow this device.
const editTimezone = ref('')

// How the display zone reads when no explicit preference is set.
const deviceZone = computed(() => deviceTimezone())
const timezoneDisplay = computed(() =>
  user.value?.timezone ? user.value.timezone : `Automatic (${deviceZone.value})`
)

// The native picker honours `max` and disables future dates; the backend
// enforces the same in update_profile so the keyboard-typed path is covered too.
const todayIso = computed(() => localIsoDate())

const nameInputRef = useTemplateRef<HTMLInputElement>('nameInputRef')
const phoneInputRef = useTemplateRef<HTMLInputElement>('phoneInputRef')
const birthdayInputRef = useTemplateRef<HTMLInputElement>('birthdayInputRef')
const locationRef =
  useTemplateRef<InstanceType<typeof LocationInput>>('locationRef')

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
    case 'timezone':
      editTimezone.value = user.value?.timezone ?? ''
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
    saveErrors.value.set(field, "Couldn't save. Try again.")
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
    case 'timezone':
      // "" clears to NULL on the server, i.e. follow the device.
      return persist(field, { timezone: editTimezone.value })
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
    <SectionHeading :icon="UserIcon" title="About you" />
    <BaseCard padded>
      <dl class="divide-line divide-y">
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
                  :maxlength="TEXT_LIMITS.name"
                  :disabled="savingFields.has('name')"
                  class="bg-surface-sunken text-ink outline-line placeholder:text-ink-placeholder focus:outline-focus min-w-0 flex-1 rounded-md px-3 py-1.5 text-base outline-1 -outline-offset-1 focus:outline-2 focus:outline-offset-2 sm:text-sm/6"
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
                class="text-state-danger-ink mt-1 text-sm"
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
                  :maxlength="TEXT_LIMITS.phone"
                  :disabled="savingFields.has('phone')"
                  class="bg-surface-sunken text-ink outline-line placeholder:text-ink-placeholder focus:outline-focus min-w-0 flex-1 rounded-md px-3 py-1.5 text-base outline-1 -outline-offset-1 focus:outline-2 focus:outline-offset-2 sm:text-sm/6"
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
                  size="compact"
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
                class="text-state-danger-ink mt-1 text-sm"
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
                  :max="todayIso"
                  :disabled="savingFields.has('birthday')"
                  class="bg-surface-sunken text-ink outline-line focus:outline-focus min-w-0 flex-1 rounded-md px-3 py-1.5 text-base outline-1 -outline-offset-1 focus:outline-2 focus:outline-offset-2 sm:text-sm/6 dark:[color-scheme:dark]"
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
                  size="compact"
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
                class="text-state-danger-ink mt-1 text-sm"
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
                :maxlength="TEXT_LIMITS.name"
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
                  size="compact"
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
                class="text-state-danger-ink mt-1 text-sm"
              >
                {{ saveErrors.get('address') }}
              </p>
            </div>
          </template>
        </DefinitionRow>

        <DefinitionRow
          label="Time zone"
          value-class="truncate"
          edit-label="Edit time zone"
          edit-testid="edit-timezone-button"
          :editing="editingFields.has('timezone')"
          @edit="openField('timezone')"
        >
          {{ timezoneDisplay }}
          <template #editor>
            <div :aria-busy="savingFields.has('timezone')">
              <TimezoneSelect
                id="profile-timezone"
                v-model="editTimezone"
                label="Time zone"
                auto-label="Automatic (follow this device)"
                :effective-zone="deviceZone"
                :disabled="savingFields.has('timezone')"
              />
              <div class="mt-2 flex flex-wrap items-center gap-2">
                <AppButton
                  size="sm"
                  :loading="savingFields.has('timezone')"
                  @click="saveField('timezone')"
                >
                  Save
                </AppButton>
                <TextButton
                  variant="secondary"
                  :disabled="savingFields.has('timezone')"
                  @click="cancelEdit('timezone')"
                >
                  Cancel
                </TextButton>
              </div>
              <p
                v-if="saveErrors.get('timezone')"
                role="alert"
                class="text-state-danger-ink mt-1 text-sm"
              >
                {{ saveErrors.get('timezone') }}
              </p>
            </div>
          </template>
        </DefinitionRow>
      </dl>
    </BaseCard>
  </div>
</template>
