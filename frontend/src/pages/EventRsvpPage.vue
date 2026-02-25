<script setup lang="ts">
import { computed } from 'vue'
import { storeToRefs } from 'pinia'
import { useRoute } from 'vue-router'
import { ArrowDownTrayIcon } from '@heroicons/vue/24/outline'
import { useAuthStore } from '@/stores/auth'
import { useHydratedEvent } from '@/composables/useHydratedEvent'
import { isPollActive } from '@/utils/poll'
import { eventHasDates } from '@/utils/event'
import { generateIcs, downloadIcs } from '@/utils/ics'
import RsvpSection from '@/components/events/RsvpSection.vue'

const route = useRoute()
const authStore = useAuthStore()
const { currentUserId } = storeToRefs(authStore)

const eventId = computed(() => route.params.id as string)

const { event } = useHydratedEvent(eventId)

function handleDownloadIcs(): void {
  if (!event.value) return
  const e = event.value
  const content = generateIcs({
    uid: e.id,
    summary: e.name,
    description: e.description,
    startDate: e.startDate,
    endDate: e.endDate,
    location: e.locationName,
    createdAt: e.createdAt,
  })
  const filename =
    e.name
      .replace(/[^a-z0-9]+/gi, '-')
      .replace(/^-|-$/g, '')
      .toLowerCase() + '.ics'
  downloadIcs(filename, content)
}
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
      <template v-else-if="eventHasDates(event)">
        <RsvpSection :event="event" :current-user-id="currentUserId" />
        <button
          type="button"
          class="mt-4 inline-flex items-center gap-1.5 text-sm text-cyan-600 hover:text-cyan-700 dark:text-cyan-400 dark:hover:text-cyan-300"
          @click="handleDownloadIcs"
        >
          <ArrowDownTrayIcon class="size-4" />
          Add to calendar
        </button>
      </template>

      <!-- No dates yet -->
      <div v-else class="text-gray-500 dark:text-stone-400">
        Dates haven't been confirmed yet.
      </div>
    </div>
  </div>
</template>
