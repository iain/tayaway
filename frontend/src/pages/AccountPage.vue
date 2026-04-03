<script setup lang="ts">
import { ref } from 'vue'
import { storeToRefs } from 'pinia'
import { useAuthStore } from '@/stores/auth'
import {
  EnvelopeIcon,
  ComputerDesktopIcon,
  KeyIcon,
} from '@heroicons/vue/24/outline'
import AlertBox from '@/components/common/AlertBox.vue'
import DefinitionRow from '@/components/common/DefinitionRow.vue'
import ChangeEmailModal from '@/components/profile/ChangeEmailModal.vue'
import SessionsList from '@/components/profile/SessionsList.vue'
import PasskeysList from '@/components/profile/PasskeysList.vue'
import PageHeader from '@/components/common/PageHeader.vue'
import BaseCard from '@/components/common/BaseCard.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'
import TextButton from '@/components/common/TextButton.vue'

const authStore = useAuthStore()
const { user } = storeToRefs(authStore)

const sessionsRef = ref<InstanceType<typeof SessionsList> | null>(null)

const editEmailOpen = ref(false)
const editEmailLoading = ref(false)
const editEmailError = ref<string | null>(null)
const editEmailSuccess = ref<string | null>(null)

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
    <PageHeader title="Account" />

    <!-- Email Section -->
    <BaseCard padded>
      <SectionHeading :icon="EnvelopeIcon" title="Email" />

      <dl class="divide-y divide-gray-200 dark:divide-stone-700">
        <DefinitionRow
          label="Email"
          value-class="truncate"
          edit-label="Edit email"
          edit-testid="edit-email-button"
          @edit="editEmailOpen = true"
        >
          {{ user?.email }}
        </DefinitionRow>

        <!-- Email change success alert -->
        <AlertBox
          v-if="editEmailSuccess"
          data-testid="email-change-success"
          variant="success"
        >
          <p class="text-sm">
            {{ editEmailSuccess }}
          </p>
        </AlertBox>
      </dl>
    </BaseCard>

    <!-- Passkeys Section -->
    <BaseCard padded class="mt-6">
      <SectionHeading :icon="KeyIcon" title="Passkeys" />
      <PasskeysList />
    </BaseCard>

    <!-- Active Sessions Section -->
    <BaseCard padded class="mt-6">
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
              ? 'Revoking…'
              : 'Sign out all other sessions'
          }}
        </TextButton>
      </SectionHeading>
      <SessionsList ref="sessionsRef" bare />
    </BaseCard>

    <ChangeEmailModal
      :open="editEmailOpen"
      :loading="editEmailLoading"
      :error="editEmailError"
      @close="editEmailOpen = false"
      @submit="handleRequestEmailChange"
    />
  </div>
</template>
