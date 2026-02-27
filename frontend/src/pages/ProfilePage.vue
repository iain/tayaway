<script setup lang="ts">
import { ref, computed } from 'vue'
import { storeToRefs } from 'pinia'
import { useAuthStore } from '@/stores/auth'
import {
  PencilIcon,
  UserIcon,
  PhoneIcon,
  ComputerDesktopIcon,
  BanknotesIcon,
} from '@heroicons/vue/24/outline'
import { formatBirthday } from '@/utils/date'
import IconButton from '@/components/common/IconButton.vue'
import EditProfileFieldModal from '@/components/profile/EditProfileFieldModal.vue'
import type {
  ProfileField,
  ProfileFieldValues,
} from '@/components/profile/EditProfileFieldModal.vue'
import ChangeEmailModal from '@/components/profile/ChangeEmailModal.vue'
import SessionsList from '@/components/profile/SessionsList.vue'
import PageHeader from '@/components/common/PageHeader.vue'
import BaseCard from '@/components/common/BaseCard.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'

const authStore = useAuthStore()
const { user } = storeToRefs(authStore)

const editField = ref<ProfileField | null>(null)
const editFieldLoading = ref(false)

const editEmailOpen = ref(false)
const editEmailLoading = ref(false)
const editEmailError = ref<string | null>(null)
const editEmailSuccess = ref<string | null>(null)

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

function openField(field: ProfileField): void {
  editField.value = field
}

async function handleSaveField(fields: ProfileFieldValues): Promise<void> {
  editFieldLoading.value = true
  try {
    await authStore.updateProfile(fields)
    editField.value = null
  } catch {
    // Error handled by mutation/toast
  } finally {
    editFieldLoading.value = false
  }
}

async function handleRequestEmailChange(email: string): Promise<void> {
  editEmailLoading.value = true
  editEmailError.value = null
  try {
    const message = await authStore.requestEmailChange(email)
    editEmailOpen.value = false
    editEmailSuccess.value = message
  } catch {
    editEmailError.value = 'Failed to send verification link. Please try again.'
  } finally {
    editEmailLoading.value = false
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
        <!-- Email -->
        <div class="group flex items-center justify-between py-3">
          <div>
            <dt class="text-sm font-medium text-gray-500 dark:text-stone-400">
              Email
            </dt>
            <dd class="text-sm text-gray-900 dark:text-white">
              {{ user?.email }}
            </dd>
          </div>
          <IconButton
            hover-reveal
            label="Edit email"
            data-testid="edit-email-button"
            @click="editEmailOpen = true"
          >
            <PencilIcon class="size-4" />
          </IconButton>
        </div>

        <!-- Email change success alert -->
        <div
          v-if="editEmailSuccess"
          data-testid="email-change-success"
          class="rounded-md bg-green-50 p-3 dark:bg-green-900/20"
        >
          <p class="text-sm text-green-700 dark:text-green-400">
            {{ editEmailSuccess }}
          </p>
        </div>

        <!-- Name -->
        <div class="group flex items-center justify-between py-3">
          <div>
            <dt class="text-sm font-medium text-gray-500 dark:text-stone-400">
              Name
            </dt>
            <dd class="text-sm text-gray-900 dark:text-white">
              {{ user?.name ?? 'Not set' }}
            </dd>
          </div>
          <IconButton
            hover-reveal
            label="Edit name"
            data-testid="edit-name-button"
            @click="openField('name')"
          >
            <PencilIcon class="size-4" />
          </IconButton>
        </div>
      </dl>
    </BaseCard>

    <!-- Contact Information Section -->
    <BaseCard padded class="mt-6">
      <SectionHeading :icon="PhoneIcon" title="Contact Information" />

      <dl class="divide-y divide-gray-200 dark:divide-stone-700">
        <!-- Phone -->
        <div class="group flex items-center justify-between py-3">
          <div>
            <dt class="text-sm font-medium text-gray-500 dark:text-stone-400">
              Phone
            </dt>
            <dd class="text-sm text-gray-900 dark:text-white">
              {{ user?.phoneNumber ?? 'Not set' }}
            </dd>
          </div>
          <IconButton
            hover-reveal
            label="Edit phone"
            data-testid="edit-contact-button"
            @click="openField('phone')"
          >
            <PencilIcon class="size-4" />
          </IconButton>
        </div>

        <!-- Birthday -->
        <div class="group flex items-center justify-between py-3">
          <div>
            <dt class="text-sm font-medium text-gray-500 dark:text-stone-400">
              Birthday
            </dt>
            <dd class="text-sm text-gray-900 dark:text-white">
              {{ user?.birthday ? formatBirthday(user.birthday) : 'Not set' }}
            </dd>
          </div>
          <IconButton
            hover-reveal
            label="Edit birthday"
            data-testid="edit-birthday-button"
            @click="openField('birthday')"
          >
            <PencilIcon class="size-4" />
          </IconButton>
        </div>

        <!-- Address -->
        <div class="group flex items-center justify-between py-3">
          <div>
            <dt class="text-sm font-medium text-gray-500 dark:text-stone-400">
              Address
            </dt>
            <dd class="text-sm text-gray-900 dark:text-white">
              {{ user?.locationName ?? 'Not set' }}
            </dd>
          </div>
          <IconButton
            hover-reveal
            label="Edit address"
            data-testid="edit-address-button"
            @click="openField('address')"
          >
            <PencilIcon class="size-4" />
          </IconButton>
        </div>
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
        <!-- IBAN -->
        <div class="group flex items-center justify-between py-3">
          <div>
            <dt class="text-sm font-medium text-gray-500 dark:text-stone-400">
              IBAN
            </dt>
            <dd class="text-sm text-gray-900 dark:text-white">
              {{ user?.iban ?? 'Not set' }}
            </dd>
          </div>
          <IconButton
            hover-reveal
            label="Edit IBAN"
            data-testid="edit-iban-button"
            @click="openField('iban')"
          >
            <PencilIcon class="size-4" />
          </IconButton>
        </div>
      </dl>
    </BaseCard>

    <!-- Active Sessions Section -->
    <BaseCard padded class="mt-6">
      <SectionHeading :icon="ComputerDesktopIcon" title="Active Sessions" />
      <SessionsList bare />
    </BaseCard>

    <!-- Unified field edit modal -->
    <EditProfileFieldModal
      :open="editField !== null"
      :field="editField ?? 'name'"
      :loading="editFieldLoading"
      :current-name="user?.name ?? null"
      :current-phone="user?.phoneNumber ?? null"
      :current-birthday="user?.birthday ?? null"
      :current-location-name="user?.locationName ?? null"
      :current-latitude="user?.latitude ?? null"
      :current-longitude="user?.longitude ?? null"
      :current-iban="user?.iban ?? null"
      @close="editField = null"
      @save="handleSaveField"
    />

    <ChangeEmailModal
      :open="editEmailOpen"
      :loading="editEmailLoading"
      :error="editEmailError"
      @close="editEmailOpen = false"
      @submit="handleRequestEmailChange"
    />
  </div>
</template>
