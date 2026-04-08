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
import DatePollSection from '@/components/events/DatePollSection.vue'
import AwaitingVotesSection from '@/components/events/AwaitingVotesSection.vue'
import OpenPollModal from '@/components/events/OpenPollModal.vue'
import AppButton from '@/components/common/AppButton.vue'
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
  return !!sd && sd < new Date().toISOString().slice(0, 10)
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
    <div v-if="!event" class="text-gray-500 dark:text-stone-400">
      Event not found
    </div>

    <div v-else>
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
      <div
        v-else-if="isPollResolved(event.datePoll)"
        class="flex flex-col items-center py-12 text-center"
      >
        <CheckCircleIcon
          class="mb-4 size-12 text-gray-400 dark:text-stone-500"
        />
        <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
          Date poll closed
        </h2>
        <p class="mt-1 max-w-sm text-gray-500 dark:text-stone-400">
          The date poll has been resolved and is no longer accepting votes.
        </p>
        <AppButton
          v-if="canOpenOrReopenPoll"
          variant="amber"
          class="mt-6"
          @click="handleReopenPoll"
        >
          <ArrowPathIcon class="size-4" />
          Reopen Poll
        </AppButton>
        <p
          v-if="canCreatePoll && eventHasStarted"
          class="mt-4 text-sm text-gray-400 dark:text-stone-500"
        >
          The poll can't be reopened because the event has already started.
        </p>
      </div>

      <!-- No poll, dates already set -->
      <div
        v-else-if="eventHasDates(event)"
        class="flex flex-col items-center py-12 text-center"
      >
        <CheckCircleIcon
          class="mb-4 size-12 text-amber-500 dark:text-amber-400"
        />
        <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
          Dates are set
        </h2>
        <p class="mt-1 max-w-sm text-gray-500 dark:text-stone-400">
          This event already has dates. Members can RSVP on the RSVP tab.
        </p>
        <p
          v-if="canOpenOrReopenPoll"
          class="mt-4 max-w-sm text-sm text-gray-400 dark:text-stone-500"
        >
          Need to reconsider? Opening a date poll lets members vote on
          alternatives. When you close the poll, the winning dates will replace
          the current ones and RSVPs will be reset.
        </p>
        <AppButton
          v-if="canOpenOrReopenPoll"
          variant="secondary"
          class="mt-4"
          @click="handleOpenPoll"
        >
          Open Date Poll Anyway
        </AppButton>
      </div>

      <!-- No poll, no dates -->
      <div v-else class="flex flex-col items-center py-12 text-center">
        <CalendarDaysIcon
          class="mb-4 size-12 text-amber-500 dark:text-amber-400"
        />
        <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
          No dates yet
        </h2>
        <p class="mt-1 max-w-sm text-gray-500 dark:text-stone-400">
          Open a date poll to let members vote on when to go. You propose date
          options, everyone votes, then you pick the winner.
        </p>
        <AppButton
          v-if="canOpenOrReopenPoll"
          class="mt-6"
          @click="handleOpenPoll"
        >
          Open Date Poll
        </AppButton>
        <p
          v-if="canCreatePoll && eventHasStarted"
          class="mt-4 text-sm text-gray-400 dark:text-stone-500"
        >
          A date poll can't be opened because the event has already started.
        </p>
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
