<script setup lang="ts">
import { computed } from 'vue'
import { storeToRefs } from 'pinia'
import { useRoute } from 'vue-router'
import { CalendarDaysIcon } from '@heroicons/vue/24/outline'
import { useAuthStore } from '@/stores'
import { useHydratedEvent } from '@/composables/useHydratedEvent'
import { isPollActive } from '@/utils/poll'
import { eventHasDates } from '@/utils/event'
import RsvpSection from '@/components/events/RsvpSection.vue'
import DateRangeDisplay from '@/components/common/DateRangeDisplay.vue'

const route = useRoute()
const authStore = useAuthStore()
const { currentMemberId } = storeToRefs(authStore)

const eventId = computed(() => route.params.id as string)

const { event } = useHydratedEvent(eventId)
</script>

<template>
  <div>
    <div v-if="!event" class="text-gray-500 dark:text-stone-400">
      Event not found
    </div>

    <div v-else>
      <!-- Event Header -->
      <header class="mb-8">
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
      </header>

      <!-- Poll still active: show info banner -->
      <div
        v-if="isPollActive(event.datePoll)"
        class="rounded-lg bg-blue-50 p-4 text-sm text-blue-700 dark:bg-blue-900/20 dark:text-blue-300"
      >
        Voting is still in progress. RSVP will be available once dates are
        confirmed.
      </div>

      <!-- Event has dates: show RSVP section -->
      <RsvpSection
        v-else-if="eventHasDates(event)"
        :event="event"
        :current-member-id="currentMemberId"
      />

      <!-- No dates yet -->
      <div v-else class="text-gray-500 dark:text-stone-400">
        Dates haven't been confirmed yet.
      </div>
    </div>
  </div>
</template>
