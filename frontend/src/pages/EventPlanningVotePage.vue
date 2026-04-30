<script setup lang="ts">
import { computed, ref } from 'vue'
import { storeToRefs } from 'pinia'
import { useRoute } from 'vue-router'
import { ArrowPathIcon, PencilSquareIcon } from '@heroicons/vue/24/outline'
import { useAuthStore } from '@/stores/auth'
import { useDatePollsStore } from '@/stores/datePolls'
import { useHydratedEvent } from '@/composables/useHydratedEvent'
import { isPollOpen, isPollResolved } from '@/utils/poll'
import AppButton from '@/components/common/AppButton.vue'
import VotingCard from '@/components/votes/VotingCard.vue'
import OpenPollModal from '@/components/events/OpenPollModal.vue'
import { can } from '@/composables/usePermission'

const route = useRoute()
const authStore = useAuthStore()
const datePollsStore = useDatePollsStore()
const { currentUserId } = storeToRefs(authStore)

const eventId = computed(() => route.params.id as string)

// Use hydrated event from pool for reactive updates
const { event } = useHydratedEvent(eventId)

const pollOpen = computed(() => isPollOpen(event.value?.datePoll))
const canManagePoll = computed(() =>
  can(event.value?.permissions, 'create_poll')
)

const dateRanges = computed(() => {
  return event.value?.datePoll?.dateRanges ?? []
})

const showReopenModal = ref(false)

async function handleReopenConfirm(deadline: string): Promise<void> {
  try {
    await datePollsStore.reopenPoll(eventId.value, deadline)
    showReopenModal.value = false
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

    <div
      v-else-if="!event.datePoll || !pollOpen"
      data-testid="poll-closed-message"
      class="py-12 text-center text-gray-500 dark:text-stone-400"
    >
      <p class="mb-2 text-lg font-semibold text-gray-900 dark:text-white">
        Voting has ended
      </p>
      <p>The date poll is closed and no longer accepting votes.</p>
      <div v-if="canManagePoll && isPollResolved(event.datePoll)" class="mt-4">
        <AppButton @click="showReopenModal = true">
          <ArrowPathIcon class="size-4" />
          Reopen Poll
        </AppButton>
      </div>
    </div>

    <div v-else>
      <!-- Date Ranges with Voting -->
      <section>
        <div class="mb-4 flex items-center justify-between">
          <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
            Date Options
          </h2>
          <router-link
            v-if="canManagePoll"
            :to="`/events/${eventId}/planning/date-ranges`"
            class="inline-flex items-center gap-1.5 text-sm text-cyan-600 underline hover:text-cyan-700 dark:text-cyan-400 dark:hover:text-cyan-300"
          >
            <PencilSquareIcon class="size-4" />
            Edit options
          </router-link>
        </div>

        <div v-if="dateRanges.length === 0" class="py-12 text-center">
          <p class="text-gray-500 dark:text-stone-400">
            No date options have been added yet. The event organiser can add
            dates to vote on.
          </p>
        </div>

        <div v-else class="space-y-4">
          <VotingCard
            v-for="dateRange in dateRanges"
            :key="dateRange.id"
            :date-range="dateRange"
            :event-id="event.id"
            :current-user-id="currentUserId"
          />
        </div>
      </section>
    </div>
  </div>

  <OpenPollModal
    :open="showReopenModal"
    title="Reopen Date Poll"
    :loading="datePollsStore.loading"
    :autofocus-submit="true"
    @confirm="handleReopenConfirm"
    @close="showReopenModal = false"
  />
</template>
