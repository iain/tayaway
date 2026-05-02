<script setup lang="ts">
import { ref, nextTick, useTemplateRef } from 'vue'
import { storeToRefs } from 'pinia'
import { useAuthStore } from '@/stores/auth'
import { EnvelopeIcon } from '@heroicons/vue/24/outline'
import AlertBox from '@/components/common/AlertBox.vue'
import DefinitionRow from '@/components/common/DefinitionRow.vue'
import BaseCard from '@/components/common/BaseCard.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'
import AppButton from '@/components/common/AppButton.vue'
import TextButton from '@/components/common/TextButton.vue'

const authStore = useAuthStore()
const { user } = storeToRefs(authStore)

const editing = ref(false)
const sending = ref(false)
const newEmail = ref('')
const error = ref<string | null>(null)
const successMessage = ref<string | null>(null)
const editInputRef = useTemplateRef<HTMLInputElement>('editInputRef')

async function openEditor(): Promise<void> {
  editing.value = true
  newEmail.value = ''
  error.value = null
  successMessage.value = null
  await nextTick()
  editInputRef.value?.focus()
}

function cancelEdit(): void {
  editing.value = false
  error.value = null
}

async function sendVerification(): Promise<void> {
  const trimmed = newEmail.value.trim()
  if (!trimmed || sending.value) return
  sending.value = true
  error.value = null
  try {
    successMessage.value = await authStore.requestEmailChange(trimmed)
    editing.value = false
  } catch {
    error.value = 'Failed to send verification link. Please try again.'
  } finally {
    sending.value = false
  }
}
</script>

<template>
  <div>
    <BaseCard padded>
      <SectionHeading :icon="EnvelopeIcon" title="Email" />

      <dl class="divide-y divide-gray-200 dark:divide-stone-700">
        <DefinitionRow
          label="Email"
          value-class="truncate"
          edit-label="Edit email"
          edit-testid="edit-email-button"
          :editing="editing"
          @edit="openEditor"
        >
          {{ user?.email }}
          <template #editor>
            <div>
              <p class="mb-2 text-xs text-gray-500 dark:text-stone-400">
                We'll send a verification link to confirm the new address.
              </p>
              <form
                class="flex items-center gap-2"
                @submit.prevent="sendVerification"
              >
                <input
                  ref="editInputRef"
                  v-model="newEmail"
                  type="email"
                  aria-label="New email address"
                  autocomplete="email"
                  placeholder="new@example.com"
                  required
                  :disabled="sending"
                  class="min-w-0 flex-1 rounded-md bg-gray-100 px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-rose-500 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-stone-500"
                  @keyup.escape="cancelEdit"
                />
                <AppButton
                  type="submit"
                  size="sm"
                  :disabled="!newEmail.trim()"
                  :loading="sending"
                  loading-label="Sending…"
                >
                  Send link
                </AppButton>
                <TextButton
                  variant="secondary"
                  :disabled="sending"
                  @click="cancelEdit"
                >
                  Cancel
                </TextButton>
              </form>
              <p
                v-if="error"
                class="mt-2 text-sm text-red-600 dark:text-red-400"
              >
                {{ error }}
              </p>
            </div>
          </template>
        </DefinitionRow>
      </dl>

      <AlertBox
        v-if="successMessage"
        data-testid="email-change-success"
        variant="success"
        class="mt-4"
      >
        <p class="text-sm">
          {{ successMessage }}
        </p>
      </AlertBox>
    </BaseCard>
  </div>
</template>
