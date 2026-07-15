<script setup lang="ts">
import { computed, ref } from 'vue'
import { storeToRefs } from 'pinia'
import { useRoute, useRouter } from 'vue-router'
import {
  ArrowPathIcon,
  CalendarDaysIcon,
  CheckCircleIcon,
} from '@heroicons/vue/24/outline'
import { useAuthStore } from '@/stores/auth'
import { useDatePollsStore } from '@/stores/datePolls'
import { useHydratedEvent } from '@/composables/useHydratedEvent'
import { isPollActive, isPollResolved } from '@/utils/poll'
import { eventHasDates } from '@/utils/event'
import { localIsoDate } from '@/utils/date'
import DatePollSection from '@/components/events/DatePollSection.vue'
import AwaitingVotesSection from '@/components/events/AwaitingVotesSection.vue'
import OpenPollModal from '@/components/events/OpenPollModal.vue'
import AppButton from '@/components/common/AppButton.vue'
import PageHeader from '@/components/common/PageHeader.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import { can } from '@/composables/usePermission'

const route = useRoute()
const router = useRouter()
const authStore = useAuthStore()
const datePollsStore = useDatePollsStore()
const { currentUserId } = storeToRefs(authStore)
const showPollModal = ref(false)
const pollModalMode = ref<'open' | 'reopen'>('open')

const eventId = computed(() => route.params.id as string)

const { event } = useHydratedEvent(eventId)

const canCreatePoll = computed(() =>
  can(event.value?.permissions, 'create_poll')
)

const eventHasStarted = computed(() => {
  const sd = event.value?.startDate
  return !!sd && sd < localIsoDate()
})

const canOpenOrReopenPoll = computed(() => {
  return canCreatePoll.value && !!event.value && !eventHasStarted.value
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
    <div v-if="!event" class="text-ink-muted">Event not found</div>

    <div v-else>
      <PageHeader title="Planning" size="sm" :icon="CalendarDaysIcon" />

      <!-- Poll open/expired: show poll sections -->
      <div
        v-if="isPollActive(event.datePoll)"
        class="grid gap-6 lg:grid-cols-2"
      >
        <DatePollSection
          :event="event"
          :is-owner="canCreatePoll"
          :current-user-id="currentUserId"
          @vote="handleVote"
        />
        <AwaitingVotesSection
          v-if="event.datePoll!.dateRanges.length > 0"
          :event="event"
          :current-user-id="currentUserId"
        />
      </div>

      <!-- Poll resolved: show closed state -->
      <EmptyState
        v-else-if="isPollResolved(event.datePoll)"
        :icon="CheckCircleIcon"
        icon-class="text-ink-muted"
        heading="Date poll closed"
        description="The date poll has been resolved and is no longer accepting votes."
      >
        <AppButton v-if="canOpenOrReopenPoll" @click="handleReopenPoll">
          <ArrowPathIcon class="size-4" />
          Reopen Poll
        </AppButton>
        <p
          v-if="canCreatePoll && eventHasStarted"
          class="text-ink-muted mt-4 text-sm"
        >
          The poll can't be reopened because the event has already started.
        </p>
      </EmptyState>

      <!-- No poll, dates already set -->
      <EmptyState
        v-else-if="eventHasDates(event)"
        :icon="CheckCircleIcon"
        heading="Dates are set"
        description="This event already has dates. Members can RSVP on the RSVP tab."
      >
        <template v-if="canOpenOrReopenPoll">
          <p class="text-ink-muted max-w-sm text-sm">
            Need to reconsider? Opening a date poll lets members vote on
            alternatives. When you close the poll, the winning dates will
            replace the current ones and RSVPs will be reset.
          </p>
          <AppButton variant="secondary" class="mt-4" @click="handleOpenPoll">
            Open Date Poll Anyway
          </AppButton>
        </template>
      </EmptyState>

      <!-- No poll, no dates -->
      <EmptyState
        v-else
        :icon="CalendarDaysIcon"
        heading="No dates yet"
        description="Open a date poll to let members vote on when to go. You propose date options, everyone votes, then you pick the winner."
      >
        <AppButton v-if="canOpenOrReopenPoll" @click="handleOpenPoll">
          Open Date Poll
        </AppButton>
        <p
          v-if="canCreatePoll && eventHasStarted"
          class="text-ink-muted mt-4 text-sm"
        >
          A date poll can't be opened because the event has already started.
        </p>
      </EmptyState>
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
