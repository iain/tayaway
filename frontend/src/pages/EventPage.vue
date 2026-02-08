<script setup lang="ts">
import { computed, ref } from 'vue'
import { storeToRefs } from 'pinia'
import { useRoute, useRouter } from 'vue-router'
import { ArrowLeftIcon, PlusIcon } from '@heroicons/vue/24/outline'
import { useAuthStore, useWebSocketStore, useEventsStore } from '@/stores'
import { useHydratedEvent } from '@/composables/useHydratedEvent'
import { useCalendar } from '@/composables/useCalendar'
import VotingCard from '@/components/votes/VotingCard.vue'
import DateRangeModal from '@/components/events/DateRangeModal.vue'

const route = useRoute()
const router = useRouter()
const authStore = useAuthStore()
const wsStore = useWebSocketStore()
const eventsStore = useEventsStore()
const { user } = storeToRefs(authStore)
const { hasSynced } = storeToRefs(wsStore)
const { loading } = storeToRefs(eventsStore)
const { addDays } = useCalendar()

const eventId = computed(() => route.params.id as string)

// Use hydrated event from pool for reactive updates
const { event } = useHydratedEvent(eventId)

const showDateRangeModal = ref(false)
const modalPreselectedStart = ref<string | null>(null)
const modalPreselectedEnd = ref<string | null>(null)

const isOwner = computed(() => {
  return user.value?.id === event.value?.userId
})

function handleBack(): void {
  router.push('/events')
}

function handleAddDateRange(): void {
  // Smart preselection: if we have existing ranges, shift the last range by 7 days
  // This preserves the day of week and length
  if (event.value && event.value.dateRanges.length > 0) {
    // Find the last range by end date
    const sortedRanges = [...event.value.dateRanges].sort((a, b) =>
      a.endDate.localeCompare(b.endDate)
    )
    const lastRange = sortedRanges[sortedRanges.length - 1]

    // Shift by 7 days to preserve day of week
    modalPreselectedStart.value = addDays(lastRange.startDate, 7)
    modalPreselectedEnd.value = addDays(lastRange.endDate, 7)
  } else {
    modalPreselectedStart.value = null
    modalPreselectedEnd.value = null
  }
  showDateRangeModal.value = true
}

async function handleDateRangeModalSave(
  startDate: string,
  endDate: string
): Promise<void> {
  if (!event.value) return

  try {
    const existingRanges = event.value.dateRanges.map((r) => ({
      start_date: r.startDate,
      end_date: r.endDate,
    }))

    await eventsStore.updateEvent(event.value.id, {
      name: event.value.name,
      description: event.value.description || undefined,
      date_ranges: [
        ...existingRanges,
        { start_date: startDate, end_date: endDate },
      ],
    })
    showDateRangeModal.value = false
  } catch {
    // Error is handled by the store
  }
}

function handleDateRangeModalClose(): void {
  showDateRangeModal.value = false
}
</script>

<template>
  <div>
    <div class="mb-6">
      <button
        type="button"
        class="inline-flex items-center gap-2 text-sm text-gray-600 hover:text-gray-900 dark:text-gray-400 dark:hover:text-white"
        @click="handleBack"
      >
        <ArrowLeftIcon class="size-4" />
        Back to Events
      </button>
    </div>

    <div v-if="!hasSynced" class="text-gray-500 dark:text-gray-400">
      Loading...
    </div>

    <div v-else-if="!event" class="text-gray-500 dark:text-gray-400">
      Event not found
    </div>

    <div v-else>
      <!-- Event Header -->
      <header class="mb-8">
        <h1
          data-testid="event-name"
          class="text-3xl font-bold tracking-tight text-gray-900 dark:text-white"
        >
          {{ event.name }}
        </h1>
        <p
          v-if="event.description"
          class="mt-2 text-lg text-gray-600 dark:text-gray-400"
        >
          {{ event.description }}
        </p>
        <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          Created by {{ event.user?.name || event.user?.email || 'Unknown' }}
        </p>
      </header>

      <!-- Date Ranges with Voting -->
      <section>
        <div class="mb-4 flex items-center justify-between">
          <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
            Vote on Date Options
          </h2>
          <button
            v-if="isOwner"
            type="button"
            class="inline-flex items-center gap-2 rounded-md bg-rose-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-rose-500"
            :disabled="loading"
            @click="handleAddDateRange"
          >
            <PlusIcon class="size-4" />
            Add Date Range
          </button>
        </div>

        <div v-if="event.dateRanges.length === 0" class="py-8 text-center">
          <p class="mb-4 text-gray-500 dark:text-gray-400">
            No date ranges have been added to this event yet.
          </p>
          <button
            v-if="isOwner"
            type="button"
            class="inline-flex items-center gap-2 rounded-md bg-rose-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-rose-500"
            :disabled="loading"
            @click="handleAddDateRange"
          >
            <PlusIcon class="size-4" />
            Add Date Range
          </button>
        </div>

        <div v-else class="space-y-4">
          <VotingCard
            v-for="dateRange in event.dateRanges"
            :key="dateRange.id"
            :date-range="dateRange"
            :event-id="event.id"
            :current-user="user"
          />
        </div>
      </section>
    </div>

    <DateRangeModal
      :open="showDateRangeModal"
      :preselected-start="modalPreselectedStart"
      :preselected-end="modalPreselectedEnd"
      @save="handleDateRangeModalSave"
      @close="handleDateRangeModalClose"
    />
  </div>
</template>
