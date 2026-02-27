<script setup lang="ts">
import { ref } from 'vue'
import { storeToRefs } from 'pinia'
import { useRouter } from 'vue-router'
import { PlusIcon, CalendarDaysIcon } from '@heroicons/vue/24/outline'
import { formatDateRange } from '@/utils/date'
import { useEventsStore, useNotificationsStore } from '@/stores'
import { useEventsList } from '@/composables/useEventsList'
import AddEventModal from '@/components/events/AddEventModal.vue'
import EventListItem from '@/components/events/EventListItem.vue'
import PageHeader from '@/components/common/PageHeader.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import DateRangeDisplay from '@/components/common/DateRangeDisplay.vue'
import AppButton from '@/components/common/AppButton.vue'

const router = useRouter()
const eventsStore = useEventsStore()
const { loading, error } = storeToRefs(eventsStore)

const showModal = ref(false)

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

function handleCreate(): void {
  showModal.value = true
}

async function handleModalSave(
  name: string,
  description: string,
  startDate: string | undefined,
  endDate: string | undefined,
  locationName: string | undefined,
  latitude: number | undefined,
  longitude: number | undefined
): Promise<void> {
  try {
    const { eventId, queued } = await eventsStore.createEvent({
      name,
      description: description || undefined,
      startDate,
      endDate,
      locationName,
      latitude,
      longitude,
    })
    showModal.value = false
    if (queued) {
      const notifications = useNotificationsStore()
      notifications.showInfo('Event will be created when back online')
    } else {
      router.push(`/events/${eventId}`)
    }
  } catch {
    // Error is handled by the store
  }
}

function handleModalClose(): void {
  showModal.value = false
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
      <AppButton data-testid="new-event-button" @click="handleCreate">
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
      heading="No events"
      description="Get started by creating a new event."
    >
      <AppButton @click="handleCreate">
        <PlusIcon class="size-5" />
        New Event
      </AppButton>
    </EmptyState>

    <div v-else data-testid="events-list" class="space-y-8">
      <section
        v-if="currentEvents.length > 0"
        data-testid="happening-now-section"
      >
        <h2 class="mb-4 text-lg font-medium text-gray-900 dark:text-white">
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
                <CalendarDaysIcon class="size-4" />
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
        <h2 class="mb-4 text-lg font-medium text-gray-900 dark:text-white">
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
                <CalendarDaysIcon class="size-4" />
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
        <h2 class="mb-4 text-lg font-medium text-gray-900 dark:text-white">
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
        <h2 class="mb-4 text-lg font-medium text-gray-900 dark:text-white">
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
                <CalendarDaysIcon class="size-4" />
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

    <AddEventModal
      :open="showModal"
      :loading="loading"
      @save="handleModalSave"
      @close="handleModalClose"
    />
  </div>
</template>
