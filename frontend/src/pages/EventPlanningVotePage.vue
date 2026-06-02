<script setup lang="ts">
import { computed, ref } from 'vue'
import { storeToRefs } from 'pinia'
import { useRoute } from 'vue-router'
import {
  ArrowPathIcon,
  CalendarDaysIcon,
  CheckCircleIcon,
  HandRaisedIcon,
  PencilSquareIcon,
} from '@heroicons/vue/24/outline'
import { useAuthStore } from '@/stores/auth'
import { useDatePollsStore } from '@/stores/datePolls'
import { useHydratedEvent } from '@/composables/useHydratedEvent'
import { isPollOpen, isPollResolved } from '@/utils/poll'
import AppButton from '@/components/common/AppButton.vue'
import VotingCard from '@/components/votes/VotingCard.vue'
import OpenPollModal from '@/components/events/OpenPollModal.vue'
import PageHeader from '@/components/common/PageHeader.vue'
import EmptyState from '@/components/common/EmptyState.vue'
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
    <div v-if="!event" class="text-ink-muted">Event not found</div>

    <div v-else>
      <PageHeader title="Vote on dates" size="sm" :icon="HandRaisedIcon">
        <router-link
          v-if="canManagePoll && event.datePoll && pollOpen"
          :to="`/events/${eventId}/planning/date-ranges`"
          class="inline-flex items-center gap-1.5 text-sm text-cyan-700 underline hover:text-cyan-800 dark:text-cyan-400 dark:hover:text-cyan-300"
        >
          <PencilSquareIcon class="size-4" />
          Edit options
        </router-link>
      </PageHeader>

      <EmptyState
        v-if="!event.datePoll || !pollOpen"
        data-testid="poll-closed-message"
        :icon="CheckCircleIcon"
        icon-class="text-ink-muted"
        heading="Voting has ended"
        description="The date poll is closed and no longer accepting votes."
      >
        <AppButton
          v-if="canManagePoll && isPollResolved(event.datePoll)"
          @click="showReopenModal = true"
        >
          <ArrowPathIcon class="size-4" />
          Reopen Poll
        </AppButton>
      </EmptyState>

      <EmptyState
        v-else-if="dateRanges.length === 0"
        :icon="CalendarDaysIcon"
        heading="No date options yet"
        description="The event organiser can add dates to vote on."
      />

      <div v-else class="space-y-4">
        <VotingCard
          v-for="dateRange in dateRanges"
          :key="dateRange.id"
          :date-range="dateRange"
          :event-id="event.id"
          :current-user-id="currentUserId"
        />
      </div>
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
