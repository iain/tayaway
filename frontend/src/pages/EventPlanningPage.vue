<script setup lang="ts">
import { computed, ref } from 'vue'
import { storeToRefs } from 'pinia'
import { useRoute, useRouter } from 'vue-router'
import { ArrowPathIcon, CalendarDaysIcon } from '@heroicons/vue/24/outline'
import { useAuthStore } from '@/stores/auth'
import { useDatePollsStore } from '@/stores/datePolls'
import { useHydratedEvent } from '@/composables/useHydratedEvent'
import { isPollActive, isPollResolved } from '@/utils/poll'
import DatePollSection from '@/components/events/DatePollSection.vue'
import AwaitingVotesSection from '@/components/events/AwaitingVotesSection.vue'
import OpenPollModal from '@/components/events/OpenPollModal.vue'
import TextButton from '@/components/common/TextButton.vue'

const route = useRoute()
const router = useRouter()
const authStore = useAuthStore()
const datePollsStore = useDatePollsStore()
const { currentUserId } = storeToRefs(authStore)
const showPollModal = ref(false)
const pollModalMode = ref<'open' | 'reopen'>('open')

const eventId = computed(() => route.params.id as string)

const { event } = useHydratedEvent(eventId)

const isOwner = computed(() => {
  return currentUserId.value === event.value?.userId
})

function handleVote(): void {
  router.push(`/events/${eventId.value}/planning/vote`)
}

function handleOpenPoll(): void {
  pollModalMode.value = 'open'
  showPollModal.value = true
}

function handleReopenPoll(): void {
  pollModalMode.value = 'reopen'
  showPollModal.value = true
}

async function handlePollModalConfirm(deadline: string): Promise<void> {
  try {
    if (pollModalMode.value === 'reopen') {
      await datePollsStore.reopenPoll(eventId.value, deadline)
    } else {
      await datePollsStore.createPoll(eventId.value, deadline)
      router.push(`/events/${eventId.value}/planning/date-ranges`)
    }
    showPollModal.value = false
  } catch {
    // Error handled by store
  }
}
</script>

<template>
  <div>
    <div v-if="!event" class="text-gray-500 dark:text-stone-400">
      Event not found
    </div>

    <div v-else>
      <div v-if="isOwner" class="mb-6 flex justify-end gap-3">
        <TextButton
          v-if="isPollResolved(event?.datePoll)"
          @click="handleReopenPoll"
        >
          <ArrowPathIcon class="size-4" />
          Reopen Poll
        </TextButton>
        <TextButton v-if="!event?.datePoll" @click="handleOpenPoll">
          <CalendarDaysIcon class="size-4" />
          Open Date Poll
        </TextButton>
      </div>

      <!-- Poll open/expired: show poll sections -->
      <div
        v-if="isPollActive(event.datePoll)"
        class="grid gap-6 lg:grid-cols-2"
      >
        <DatePollSection
          :event="event"
          :is-owner="isOwner"
          :current-user-id="currentUserId"
          @vote="handleVote"
        />
        <AwaitingVotesSection
          v-if="event.datePoll!.dateRanges.length > 0"
          :event="event"
          :current-user-id="currentUserId"
        />
      </div>

      <!-- Poll resolved: show closed message -->
      <div
        v-else-if="isPollResolved(event.datePoll)"
        class="py-8 text-center text-gray-500 dark:text-stone-400"
      >
        <p class="text-lg font-medium">Voting is closed</p>
        <p>The date poll is no longer accepting votes.</p>
      </div>

      <!-- No poll + not owner: show placeholder -->
      <div v-else-if="!isOwner" class="text-gray-500 dark:text-stone-400">
        No date poll has been opened yet.
      </div>
    </div>
  </div>

  <OpenPollModal
    :open="showPollModal"
    :title="pollModalMode === 'reopen' ? 'Reopen Date Poll' : 'Open Date Poll'"
    :loading="datePollsStore.loading"
    :autofocus-submit="pollModalMode === 'reopen'"
    @confirm="handlePollModalConfirm"
    @close="showPollModal = false"
  />
</template>
