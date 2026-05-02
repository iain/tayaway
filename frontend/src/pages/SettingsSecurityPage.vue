<script setup lang="ts">
import { ref } from 'vue'
import { ComputerDesktopIcon, KeyIcon } from '@heroicons/vue/24/outline'
import SessionsList from '@/components/profile/SessionsList.vue'
import PasskeysList from '@/components/profile/PasskeysList.vue'
import BaseCard from '@/components/common/BaseCard.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'
import TextButton from '@/components/common/TextButton.vue'

const sessionsRef = ref<InstanceType<typeof SessionsList> | null>(null)
</script>

<template>
  <div class="space-y-6">
    <BaseCard padded>
      <SectionHeading :icon="KeyIcon" title="Passkeys" />
      <PasskeysList />
    </BaseCard>

    <BaseCard padded>
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
  </div>
</template>
