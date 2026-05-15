<script setup lang="ts">
import { ref, nextTick, useTemplateRef } from 'vue'
import { storeToRefs } from 'pinia'
import { useAuthStore } from '@/stores/auth'
import {
  ComputerDesktopIcon,
  EnvelopeIcon,
  KeyIcon,
} from '@heroicons/vue/24/outline'
import AlertBox from '@/components/common/AlertBox.vue'
import DefinitionRow from '@/components/common/DefinitionRow.vue'
import BaseCard from '@/components/common/BaseCard.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'
import AppButton from '@/components/common/AppButton.vue'
import TextButton from '@/components/common/TextButton.vue'
import PasskeysList from '@/components/profile/PasskeysList.vue'
import SessionsList from '@/components/profile/SessionsList.vue'

const authStore = useAuthStore()
const { user } = storeToRefs(authStore)

const editingEmail = ref(false)
const sending = ref(false)
const newEmail = ref('')
const error = ref<string | null>(null)
const successMessage = ref<string | null>(null)
const editInputRef = useTemplateRef<HTMLInputElement>('editInputRef')

async function openEmailEditor(): Promise<void> {
  editingEmail.value = true
  newEmail.value = ''
  error.value = null
  successMessage.value = null
  await nextTick()
  editInputRef.value?.focus()
}

function cancelEmailEdit(): void {
  editingEmail.value = false
  error.value = null
}

async function sendVerification(): Promise<void> {
  const trimmed = newEmail.value.trim()
  if (!trimmed || sending.value) return
  sending.value = true
  error.value = null
  try {
    successMessage.value = await authStore.requestEmailChange(trimmed)
    editingEmail.value = false
  } catch {
    error.value = 'Failed to send verification link. Please try again.'
  } finally {
    sending.value = false
  }
}

const sessionsRef = ref<InstanceType<typeof SessionsList> | null>(null)
</script>

<template>
  <div class="space-y-6">
    <section>
      <SectionHeading :icon="EnvelopeIcon" title="Email" />
      <BaseCard padded>
        <dl class="divide-line divide-y">
        <DefinitionRow
          label="Email"
          value-class="truncate"
          edit-label="Edit email"
          edit-testid="edit-email-button"
          :editing="editingEmail"
          @edit="openEmailEditor"
        >
          {{ user?.email }}
          <template #editor>
            <div>
              <p class="text-ink-muted mb-2 text-xs">
                We'll send a verification link to confirm the new address.
              </p>
              <form
                class="flex flex-wrap items-center gap-2"
                :aria-busy="sending"
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
                  class="bg-surface-sunken text-ink outline-line placeholder:text-ink-placeholder min-w-0 flex-1 rounded-md px-3 py-1.5 text-base outline-1 -outline-offset-1 focus:outline-2 focus:outline-offset-2 focus:outline-focus sm:text-sm/6"
                  @keyup.escape="cancelEmailEdit"
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
                  @click="cancelEmailEdit"
                >
                  Cancel
                </TextButton>
              </form>
              <p
                v-if="error"
                role="alert"
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
    </section>

    <section>
      <SectionHeading :icon="KeyIcon" title="Passkeys" />
      <BaseCard padded>
        <PasskeysList />
      </BaseCard>
    </section>

    <section>
      <SectionHeading :icon="ComputerDesktopIcon" title="Active Sessions">
        <TextButton
          v-if="
            sessionsRef?.hasOtherSessions &&
            !sessionsRef?.loading &&
            !sessionsRef?.error
          "
          variant="danger"
          :disabled="sessionsRef?.revokingAll"
          @click="sessionsRef?.endAllOtherSessions()"
        >
          {{
            sessionsRef?.revokingAll
              ? 'Logging out…'
              : 'Log out all other sessions'
          }}
        </TextButton>
      </SectionHeading>
      <BaseCard padded>
        <SessionsList ref="sessionsRef" bare />
      </BaseCard>
    </section>
  </div>
</template>
