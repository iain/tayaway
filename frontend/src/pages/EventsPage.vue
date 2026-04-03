<script setup lang="ts">
import { ref } from 'vue'
import { storeToRefs } from 'pinia'
import { useRouter } from 'vue-router'
import { PlusIcon, CalendarDaysIcon } from '@heroicons/vue/24/outline'
import { formatDateRange } from '@/utils/date'
import { useEventsStore } from '@/stores'
import { useEventsList } from '@/composables/useEventsList'
import CreateEventWizard from '@/components/events/CreateEventWizard.vue'
import EventListItem from '@/components/events/EventListItem.vue'
import PageHeader from '@/components/common/PageHeader.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import DateRangeDisplay from '@/components/common/DateRangeDisplay.vue'
import AppButton from '@/components/common/AppButton.vue'

const router = useRouter()
const eventsStore = useEventsStore()
const { error } = storeToRefs(eventsStore)

const showWizard = ref(false)

const {
  currentEvents,
  upcomingEvents,
  pastEvents,
  planningEvents,
  hasEvents,
  getEventOwner,
  getDateRanges,
} = useEventsList()

function getOwnerName(userId: string): string {
  const owner = getEventOwner(userId)
  return owner?.name || owner?.email || 'Unknown'
}

function handleView(id: string): void {
  router.push(`/events/${id}`)
}

function formatDateRangeSummary(
  ranges: { startDate: string; endDate: string }[]
): string {
  if (ranges.length === 0) return 'No dates'
  if (ranges.length === 1)
    return formatDateRange(ranges[0]!.startDate, ranges[0]!.endDate)
  return `${ranges.length} date ranges`
}
</script>

<template>
  <div>
    <PageHeader title="Events" data-testid="page-title">
      <AppButton data-testid="new-event-button" @click="showWizard = true">
        <PlusIcon class="size-5" />
        New Event
      </AppButton>
    </PageHeader>

    <div v-if="error" class="text-red-600 dark:text-red-400">
      {{ error }}
    </div>

    <EmptyState
      v-else-if="!hasEvents"
      :icon="CalendarDaysIcon"
      heading="No events yet"
      description="Create an event to start planning dates, splitting costs, and organising your group."
    >
      <AppButton @click="showWizard = true">
        <PlusIcon class="size-5" />
        New Event
      </AppButton>
    </EmptyState>

    <div v-else data-testid="events-list" class="space-y-8">
      <section
        v-if="currentEvents.length > 0"
        data-testid="happening-now-section"
      >
        <h2 class="mb-4 text-lg font-semibold text-gray-900 dark:text-white">
          Happening Now
        </h2>
        <ul class="space-y-4">
          <EventListItem
            v-for="event in currentEvents"
            :key="event.id"
            :event="event"
            :owner-name="getOwnerName(event.userId)"
            @click="handleView(event.id)"
          >
            <template #meta>
              <span class="inline-flex items-center gap-1">
                <CalendarDaysIcon
                  class="size-4 text-amber-600 dark:text-amber-400"
                />
                <DateRangeDisplay
                  :start-date="event.startDate!"
                  :end-date="event.endDate!"
                />
              </span>
            </template>
          </EventListItem>
        </ul>
      </section>

      <section v-if="upcomingEvents.length > 0" data-testid="upcoming-section">
        <h2 class="mb-4 text-lg font-semibold text-gray-900 dark:text-white">
          Upcoming
        </h2>
        <ul class="space-y-4">
          <EventListItem
            v-for="event in upcomingEvents"
            :key="event.id"
            :event="event"
            :owner-name="getOwnerName(event.userId)"
            @click="handleView(event.id)"
          >
            <template #meta>
              <span class="inline-flex items-center gap-1">
                <CalendarDaysIcon
                  class="size-4 text-amber-600 dark:text-amber-400"
                />
                <DateRangeDisplay
                  :start-date="event.startDate!"
                  :end-date="event.endDate!"
                />
              </span>
            </template>
          </EventListItem>
        </ul>
      </section>

      <section v-if="planningEvents.length > 0">
        <h2 class="mb-4 text-lg font-semibold text-gray-900 dark:text-white">
          Planning
        </h2>
        <ul class="space-y-4">
          <EventListItem
            v-for="event in planningEvents"
            :key="event.id"
            :event="event"
            :owner-name="getOwnerName(event.userId)"
            @click="handleView(event.id)"
          >
            <template #meta>
              <span>{{ formatDateRangeSummary(getDateRanges(event.id)) }}</span>
            </template>
          </EventListItem>
        </ul>
      </section>

      <section v-if="pastEvents.length > 0">
        <h2 class="mb-4 text-lg font-semibold text-gray-900 dark:text-white">
          Past
        </h2>
        <ul class="space-y-4">
          <EventListItem
            v-for="event in pastEvents"
            :key="event.id"
            :event="event"
            :owner-name="getOwnerName(event.userId)"
            @click="handleView(event.id)"
          >
            <template #meta>
              <span class="inline-flex items-center gap-1">
                <CalendarDaysIcon
                  class="size-4 text-amber-600 dark:text-amber-400"
                />
                <DateRangeDisplay
                  :start-date="event.startDate!"
                  :end-date="event.endDate!"
                />
              </span>
            </template>
          </EventListItem>
        </ul>
      </section>
    </div>

    <CreateEventWizard :open="showWizard" @close="showWizard = false" />
  </div>
</template>
