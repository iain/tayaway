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
import DatePollSection from '@/components/events/DatePollSection.vue'
import AwaitingVotesSection from '@/components/events/AwaitingVotesSection.vue'
import OpenPollModal from '@/components/events/OpenPollModal.vue'
import AppButton from '@/components/common/AppButton.vue'

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

const eventHasStarted = computed(() => {
  const sd = event.value?.startDate
  return !!sd && sd < new Date().toISOString().slice(0, 10)
})

const canOpenOrReopenPoll = computed(() => {
  return isOwner.value && !!event.value && !eventHasStarted.value
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

      <!-- Poll resolved: show closed state -->
      <div
        v-else-if="isPollResolved(event.datePoll)"
        class="flex flex-col items-center py-12 text-center"
      >
        <CheckCircleIcon
          class="mb-4 size-12 text-gray-400 dark:text-stone-500"
        />
        <h2 class="text-lg font-semibold text-gray-900 dark:text-stone-100">
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
          v-if="isOwner && eventHasStarted"
          class="mt-4 text-sm text-gray-400 dark:text-stone-500"
        >
          The poll can't be reopened because the event has already started.
        </p>
      </div>

      <!-- No poll: show empty state -->
      <div v-else class="flex flex-col items-center py-12 text-center">
        <CalendarDaysIcon
          class="mb-4 size-12 text-amber-500 dark:text-amber-400"
        />
        <h2 class="text-lg font-semibold text-gray-900 dark:text-stone-100">
          Plan your event dates
        </h2>
        <p class="mt-1 max-w-sm text-gray-500 dark:text-stone-400">
          Use a date poll to find the best dates for your event. Members vote on
          proposed dates and the organiser picks the winner.
        </p>
        <ol class="mt-6 space-y-3 text-left text-sm">
          <li class="flex gap-3">
            <span
              class="flex size-6 shrink-0 items-center justify-center rounded-full bg-sky-100 text-xs font-semibold text-sky-700 dark:bg-sky-900 dark:text-sky-300"
              >1</span
            >
            <span class="text-gray-700 dark:text-stone-300"
              ><strong>Create a date poll</strong> — Set a voting deadline</span
            >
          </li>
          <li class="flex gap-3">
            <span
              class="flex size-6 shrink-0 items-center justify-center rounded-full bg-sky-100 text-xs font-semibold text-sky-700 dark:bg-sky-900 dark:text-sky-300"
              >2</span
            >
            <span class="text-gray-700 dark:text-stone-300"
              ><strong>Add date options</strong> — Propose date ranges to vote
              on</span
            >
          </li>
          <li class="flex gap-3">
            <span
              class="flex size-6 shrink-0 items-center justify-center rounded-full bg-sky-100 text-xs font-semibold text-sky-700 dark:bg-sky-900 dark:text-sky-300"
              >3</span
            >
            <span class="text-gray-700 dark:text-stone-300"
              ><strong>Members vote</strong> — Everyone picks their preferred
              dates</span
            >
          </li>
          <li class="flex gap-3">
            <span
              class="flex size-6 shrink-0 items-center justify-center rounded-full bg-sky-100 text-xs font-semibold text-sky-700 dark:bg-sky-900 dark:text-sky-300"
              >4</span
            >
            <span class="text-gray-700 dark:text-stone-300"
              ><strong>Confirm the dates</strong> — Lock in the best date for
              the event</span
            >
          </li>
        </ol>
        <AppButton
          v-if="canOpenOrReopenPoll"
          class="mt-6"
          @click="handleOpenPoll"
        >
          Open Date Poll
        </AppButton>
        <p
          v-if="isOwner && eventHasStarted"
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
