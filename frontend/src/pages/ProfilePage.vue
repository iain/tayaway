<script setup lang="ts">
import { ref } from 'vue'
import { storeToRefs } from 'pinia'
import { useAuthStore } from '@/stores/auth'
import EditNameModal from '@/components/profile/EditNameModal.vue'
import ChangeEmailModal from '@/components/profile/ChangeEmailModal.vue'
import SessionsList from '@/components/profile/SessionsList.vue'
import PageHeader from '@/components/common/PageHeader.vue'
import BaseCard from '@/components/common/BaseCard.vue'
import TextButton from '@/components/common/TextButton.vue'

const authStore = useAuthStore()
const { user } = storeToRefs(authStore)

const editNameOpen = ref(false)
const editNameLoading = ref(false)
const editNameError = ref<string | null>(null)

const editEmailOpen = ref(false)
const editEmailLoading = ref(false)
const editEmailError = ref<string | null>(null)
const editEmailSuccess = ref<string | null>(null)

async function handleSaveName(name: string): Promise<void> {
  editNameLoading.value = true
  editNameError.value = null
  try {
    await authStore.updateName(name)
    editNameOpen.value = false
  } catch {
    editNameError.value = 'Failed to update name. Please try again.'
  } finally {
    editNameLoading.value = false
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

    <BaseCard>
      <div class="px-4 py-5 sm:p-6">
        <div class="space-y-6">
          <div>
            <h3 class="text-lg font-medium text-gray-900 dark:text-white">
              Account Information
            </h3>
            <p class="mt-1 text-sm text-gray-500 dark:text-stone-400">
              Your account details.
            </p>
          </div>

          <div class="border-t border-gray-200 pt-6 dark:border-stone-700">
            <dl class="divide-y divide-gray-200 dark:divide-stone-700">
              <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
                <dt
                  class="text-sm font-medium text-gray-500 dark:text-stone-400"
                >
                  Name
                </dt>
                <dd
                  class="mt-1 flex items-center gap-2 text-sm text-gray-900 sm:col-span-2 sm:mt-0 dark:text-white"
                >
                  <span>{{ user?.name ?? 'Not set' }}</span>
                  <TextButton
                    data-testid="edit-name-button"
                    @click="editNameOpen = true"
                  >
                    Edit
                  </TextButton>
                </dd>
              </div>
              <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
                <dt
                  class="text-sm font-medium text-gray-500 dark:text-stone-400"
                >
                  Email address
                </dt>
                <dd
                  class="mt-1 flex items-center gap-2 text-sm text-gray-900 sm:col-span-2 sm:mt-0 dark:text-white"
                >
                  <span>{{ user?.email }}</span>
                  <TextButton
                    data-testid="edit-email-button"
                    @click="editEmailOpen = true"
                  >
                    Edit
                  </TextButton>
                </dd>
              </div>
            </dl>
          </div>
        </div>
      </div>
    </BaseCard>
    <div
      v-if="editEmailSuccess"
      data-testid="email-change-success"
      class="mt-4 rounded-md bg-green-50 p-4 dark:bg-green-900/20"
    >
      <p class="text-sm text-green-700 dark:text-green-400">
        {{ editEmailSuccess }}
      </p>
    </div>
    <SessionsList class="mt-6" />
    <EditNameModal
      :open="editNameOpen"
      :loading="editNameLoading"
      :current-name="user?.name ?? null"
      @close="editNameOpen = false"
      @save="handleSaveName"
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
