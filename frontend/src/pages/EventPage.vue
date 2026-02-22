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
import RsvpSection from '@/components/events/RsvpSection.vue'
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

// Use hydrated event from pool for reactive updates
const { event } = useHydratedEvent(eventId)

const isOwner = computed(() => {
  return currentMemberId.value === event.value?.memberId
})

function handleVote(): void {
  router.push(`/events/${eventId.value}/vote`)
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
      router.push(`/events/${eventId.value}/date-ranges`)
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

      <!-- Stats Grid -->
      <div class="grid gap-6 lg:grid-cols-2">
        <!-- Date Poll Section (only when poll exists and not resolved) -->
        <DatePollSection
          v-if="isPollActive(event.datePoll)"
          :event="event"
          :is-owner="isOwner"
          :current-member-id="currentMemberId"
          @vote="handleVote"
        />

        <!-- RSVPs (shown when event has dates) -->
        <RsvpSection
          v-if="eventHasDates(event)"
          :event="event"
          :current-member-id="currentMemberId"
        />

        <!-- Who Hasn't Voted (only when poll exists and not resolved) -->
        <AwaitingVotesSection
          v-if="
            isPollActive(event.datePoll) &&
            event.datePoll!.dateRanges.length > 0
          "
          :event="event"
          :current-member-id="currentMemberId"
        />
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
