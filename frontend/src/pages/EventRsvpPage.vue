<script setup lang="ts">
import { computed, ref } from 'vue'
import { storeToRefs } from 'pinia'
import { useRoute } from 'vue-router'
import {
  ArrowDownTrayIcon,
  CalendarDaysIcon,
  ClockIcon,
  UserGroupIcon,
} from '@heroicons/vue/24/outline'
import { useAuthStore } from '@/stores/auth'
import { useHydratedEvent } from '@/composables/useHydratedEvent'
import { isPollActive } from '@/utils/poll'
import { eventHasDates } from '@/utils/event'
import { generateIcs, downloadIcs } from '@/utils/ics'
import { useEventsStore } from '@/stores'
import { useObjectPoolStore } from '@/stores/objectPool'
import RsvpSection from '@/components/events/RsvpSection.vue'
import BaseModal from '@/components/common/BaseModal.vue'
import AppButton from '@/components/common/AppButton.vue'
import TextButton from '@/components/common/TextButton.vue'
import PageHeader from '@/components/common/PageHeader.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import { can } from '@/composables/usePermission'

const route = useRoute()
const authStore = useAuthStore()
const { currentUserId } = storeToRefs(authStore)

const eventId = computed(() => route.params.id as string)

const { event } = useHydratedEvent(eventId)

const canEditEvent = computed(() => can(event.value?.permissions, 'edit'))

const eventsStore = useEventsStore()
const { loading } = storeToRefs(eventsStore)
const datesBlockedOpen = ref(false)

const pool = useObjectPoolStore()
const hasExpenses = computed(() => {
  return pool.getAll('expense').some((e) => e.eventId === eventId.value)
})

// Inline date editing
const showDateForm = ref(false)
const editStartDate = ref('')
const editEndDate = ref('')

function openDatesEdit(): void {
  if (hasExpenses.value) {
    datesBlockedOpen.value = true
    return
  }
  editStartDate.value = event.value?.startDate ?? ''
  editEndDate.value = event.value?.endDate ?? ''
  showDateForm.value = true
}

async function saveDates(): Promise<void> {
  if (!event.value || loading.value) return
  await eventsStore.updateEvent(eventId.value, {
    name: event.value.name,
    startDate: editStartDate.value || undefined,
    endDate: editEndDate.value || undefined,
  })
  showDateForm.value = false
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
      <PageHeader title="RSVP" size="sm" :icon="UserGroupIcon" />

      <!-- Poll still active: show empty state -->
      <EmptyState
        v-if="isPollActive(event.datePoll)"
        :icon="ClockIcon"
        heading="Voting in progress"
        description="A date poll is open and members are voting. RSVP will be available once dates are confirmed."
      >
        <router-link
          :to="`/events/${event.id}/planning`"
          class="text-sm text-cyan-600 hover:text-cyan-700 dark:text-cyan-400 dark:hover:text-cyan-300"
        >
          Go to Planning
        </router-link>
      </EmptyState>

      <!-- Event has dates: show RSVP section -->
      <template v-else-if="eventHasDates(event)">
        <RsvpSection :event="event" :current-user-id="currentUserId" />
        <TextButton class="mt-4" @click="handleDownloadIcs">
          <ArrowDownTrayIcon class="size-4" />
          Add to calendar
        </TextButton>
      </template>

      <!-- No dates yet: show empty state with inline date form -->
      <EmptyState
        v-else
        :icon="CalendarDaysIcon"
        heading="No dates confirmed yet"
        description="Once the event dates have been decided, you'll be able to RSVP here."
      >
        <div class="flex flex-col items-center gap-3">
          <router-link
            :to="`/events/${event.id}/planning`"
            class="text-sm font-medium text-cyan-600 hover:text-cyan-700 dark:text-cyan-400 dark:hover:text-cyan-300"
          >
            Go to Planning
          </router-link>

          <template v-if="canEditEvent">
            <form
              v-if="showDateForm"
              class="flex flex-wrap items-end justify-center gap-3"
              @submit.prevent="saveDates"
            >
              <div>
                <label
                  for="rsvp-start-date"
                  class="mb-1 block text-xs font-medium text-gray-500 dark:text-stone-400"
                >
                  Start date
                </label>
                <input
                  id="rsvp-start-date"
                  v-model="editStartDate"
                  type="date"
                  :disabled="loading"
                  class="rounded-md bg-gray-100 px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:outline-offset-2 focus:outline-focus dark:bg-white/5 dark:text-white dark:[color-scheme:dark] dark:outline-white/10"
                />
              </div>
              <div>
                <label
                  for="rsvp-end-date"
                  class="mb-1 block text-xs font-medium text-gray-500 dark:text-stone-400"
                >
                  End date
                </label>
                <input
                  id="rsvp-end-date"
                  v-model="editEndDate"
                  type="date"
                  :disabled="loading"
                  class="rounded-md bg-gray-100 px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:outline-offset-2 focus:outline-focus dark:bg-white/5 dark:text-white dark:[color-scheme:dark] dark:outline-white/10"
                />
              </div>
              <AppButton type="submit" size="sm" :loading="loading">
                Save
              </AppButton>
              <TextButton
                variant="secondary"
                :disabled="loading"
                @click="showDateForm = false"
              >
                Cancel
              </TextButton>
            </form>
            <TextButton v-else variant="secondary" @click="openDatesEdit">
              or set dates directly
            </TextButton>
          </template>
        </div>
      </EmptyState>

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
          <AppButton variant="secondary" @click="datesBlockedOpen = false">
            Got it
          </AppButton>
        </div>
      </BaseModal>
    </div>
  </div>
</template>
