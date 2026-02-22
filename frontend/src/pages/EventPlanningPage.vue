<script setup lang="ts">
import { computed, ref } from 'vue'
import { storeToRefs } from 'pinia'
import { useRoute, useRouter } from 'vue-router'
import { ArrowPathIcon, CalendarDaysIcon } from '@heroicons/vue/24/outline'
import { useAuthStore } from '@/stores'
import { useDatePollsStore } from '@/stores/datePolls'
import { useHydratedEvent } from '@/composables/useHydratedEvent'
import { isPollActive, isPollResolved } from '@/utils/poll'
import { eventHasDates } from '@/utils/event'
import DatePollSection from '@/components/events/DatePollSection.vue'
import AwaitingVotesSection from '@/components/events/AwaitingVotesSection.vue'
import OpenPollModal from '@/components/events/OpenPollModal.vue'
import TextButton from '@/components/common/TextButton.vue'
import DateRangeDisplay from '@/components/common/DateRangeDisplay.vue'

const route = useRoute()
const router = useRouter()
const authStore = useAuthStore()
const datePollsStore = useDatePollsStore()
const { currentMemberId } = storeToRefs(authStore)
const showPollModal = ref(false)
const pollModalMode = ref<'open' | 'reopen'>('open')

const eventId = computed(() => route.params.id as string)

const { event } = useHydratedEvent(eventId)

const isOwner = computed(() => {
  return currentMemberId.value === event.value?.memberId
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
      <!-- Event Header -->
      <header class="mb-8">
        <div class="flex items-start justify-between">
          <div>
            <h1
              data-testid="event-name"
              class="text-3xl font-bold tracking-tight text-gray-900 dark:text-white"
            >
              {{ event.name }}
            </h1>
            <p
              v-if="event.description"
              class="mt-2 text-lg text-gray-600 dark:text-stone-400"
            >
              {{ event.description }}
            </p>
            <p
              v-if="eventHasDates(event)"
              data-testid="event-dates"
              class="mt-2 flex items-center gap-1.5 text-sm text-gray-600 dark:text-stone-300"
            >
              <CalendarDaysIcon class="size-4" />
              <DateRangeDisplay
                :start-date="event.startDate!"
                :end-date="event.endDate!"
              />
            </p>
            <p class="mt-2 text-sm text-gray-500 dark:text-stone-400">
              Created by
              {{ event.member?.name || event.member?.email || 'Unknown' }}
            </p>
          </div>
          <div v-if="isOwner" class="ml-4 flex shrink-0 items-center gap-3">
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
        </div>
      </header>

      <!-- Poll open/expired: show poll sections -->
      <div
        v-if="isPollActive(event.datePoll)"
        class="grid gap-6 lg:grid-cols-2"
      >
        <DatePollSection
          :event="event"
          :is-owner="isOwner"
          :current-member-id="currentMemberId"
          @vote="handleVote"
        />
        <AwaitingVotesSection
          v-if="event.datePoll!.dateRanges.length > 0"
          :event="event"
          :current-member-id="currentMemberId"
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
