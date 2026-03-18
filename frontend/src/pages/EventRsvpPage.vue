<script setup lang="ts">
import { computed, ref } from 'vue'
import { storeToRefs } from 'pinia'
import { useRoute } from 'vue-router'
import {
  ArrowDownTrayIcon,
  CalendarDaysIcon,
  ClockIcon,
} from '@heroicons/vue/24/outline'
import { useAuthStore } from '@/stores/auth'
import { useHydratedEvent } from '@/composables/useHydratedEvent'
import { isPollActive } from '@/utils/poll'
import { eventHasDates } from '@/utils/event'
import { generateIcs, downloadIcs } from '@/utils/ics'
import { useEventsStore } from '@/stores'
import { useObjectPoolStore } from '@/stores/objectPool'
import RsvpSection from '@/components/events/RsvpSection.vue'
import EditEventModal from '@/components/events/EditEventModal.vue'
import BaseModal from '@/components/common/BaseModal.vue'
import AppButton from '@/components/common/AppButton.vue'
import TextButton from '@/components/common/TextButton.vue'

const route = useRoute()
const authStore = useAuthStore()
const { currentUserId } = storeToRefs(authStore)

const eventId = computed(() => route.params.id as string)

const { event } = useHydratedEvent(eventId)

const isOwner = computed(() => currentUserId.value === event.value?.userId)

const eventsStore = useEventsStore()
const { loading } = storeToRefs(eventsStore)
const modalOpen = ref(false)
const datesBlockedOpen = ref(false)

const pool = useObjectPoolStore()
const hasExpenses = computed(() => {
  void pool.version
  return pool.getAll('expense').some((e) => e.eventId === eventId.value)
})

function openDatesEdit(): void {
  if (hasExpenses.value) {
    datesBlockedOpen.value = true
    return
  }
  modalOpen.value = true
}

async function handleSave(data: {
  name: string
  description: string | undefined
  startDate: string | null
  endDate: string | null
  locationName: string | undefined
  latitude: number | undefined
  longitude: number | undefined
}): Promise<void> {
  if (!event.value) return
  await eventsStore.updateEvent(eventId.value, {
    name: data.name,
    description: data.description,
    startDate: data.startDate ?? undefined,
    endDate: data.endDate ?? undefined,
    locationName: data.locationName,
    latitude: data.latitude,
    longitude: data.longitude,
  })
  modalOpen.value = false
}

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
      <!-- Poll still active: show empty state -->
      <div
        v-if="isPollActive(event.datePoll)"
        class="flex flex-col items-center py-12 text-center"
      >
        <ClockIcon class="mb-4 size-12 text-gray-400 dark:text-stone-500" />
        <h2 class="text-lg font-semibold text-gray-900 dark:text-stone-100">
          Voting in progress
        </h2>
        <p class="mt-1 max-w-sm text-gray-500 dark:text-stone-400">
          A date poll is open and members are voting. RSVP will be available
          once dates are confirmed.
        </p>
        <router-link
          :to="`/events/${event.id}/planning`"
          class="mt-4 text-sm text-cyan-600 hover:text-cyan-700 dark:text-cyan-400 dark:hover:text-cyan-300"
        >
          Go to Planning
        </router-link>
      </div>

      <!-- Event has dates: show RSVP section -->
      <template v-else-if="eventHasDates(event)">
        <RsvpSection :event="event" :current-user-id="currentUserId" />
        <TextButton class="mt-4" @click="handleDownloadIcs">
          <ArrowDownTrayIcon class="size-4" />
          Add to calendar
        </TextButton>
      </template>

      <!-- No dates yet: show empty state -->
      <div v-else class="flex flex-col items-center py-12 text-center">
        <CalendarDaysIcon
          class="mb-4 size-12 text-gray-400 dark:text-stone-500"
        />
        <h2 class="text-lg font-semibold text-gray-900 dark:text-stone-100">
          No dates confirmed yet
        </h2>
        <p class="mt-1 max-w-sm text-gray-500 dark:text-stone-400">
          Once the event dates have been decided, you'll be able to RSVP here.
        </p>
        <router-link
          :to="`/events/${event.id}/planning`"
          class="mt-4 text-sm font-medium text-cyan-600 hover:text-cyan-700 dark:text-cyan-400 dark:hover:text-cyan-300"
        >
          Go to Planning
        </router-link>
        <TextButton
          v-if="isOwner"
          variant="secondary"
          class="mt-2"
          @click="openDatesEdit"
        >
          or set dates directly
        </TextButton>
      </div>

      <EditEventModal
        v-if="event"
        :open="modalOpen"
        field="dates"
        :current-name="event.name"
        :current-description="event.description"
        :current-start-date="event.startDate"
        :current-end-date="event.endDate"
        :current-location-name="event.locationName"
        :current-latitude="event.latitude"
        :current-longitude="event.longitude"
        :loading="loading"
        @close="modalOpen = false"
        @save="handleSave"
      />

      <BaseModal
        :open="datesBlockedOpen"
        title="Can't change dates"
        @close="datesBlockedOpen = false"
      >
        <p class="text-gray-600 dark:text-stone-300">
          This event has expenses tied to the current dates. Delete or adjust
          the expenses first, then you can change the event dates.
        </p>
        <div class="mt-6 flex justify-end">
          <AppButton variant="cyan" @click="datesBlockedOpen = false">
            Got it
          </AppButton>
        </div>
      </BaseModal>
    </div>
  </div>
</template>
