<script setup lang="ts">
import { computed } from 'vue'
import { storeToRefs } from 'pinia'
import { useRoute } from 'vue-router'
import { useAuthStore } from '@/stores'
import { useHydratedEvent } from '@/composables/useHydratedEvent'
import { isPollActive } from '@/utils/poll'
import { eventHasDates } from '@/utils/event'
import RsvpSection from '@/components/events/RsvpSection.vue'

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
