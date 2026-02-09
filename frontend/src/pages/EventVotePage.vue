<script setup lang="ts">
import { computed, ref } from 'vue'
import { storeToRefs } from 'pinia'
import { useRoute, useRouter } from 'vue-router'
import { ArrowLeftIcon, PlusIcon } from '@heroicons/vue/24/outline'
import { useAuthStore, useWebSocketStore, useDatePollsStore } from '@/stores'
import { useHydratedEvent } from '@/composables/useHydratedEvent'
import { useCalendar } from '@/composables/useCalendar'
import VotingCard from '@/components/votes/VotingCard.vue'
import DateRangeModal from '@/components/events/DateRangeModal.vue'

const route = useRoute()
const router = useRouter()
const authStore = useAuthStore()
const wsStore = useWebSocketStore()
const datePollsStore = useDatePollsStore()
const { user } = storeToRefs(authStore)
const { hasSynced } = storeToRefs(wsStore)
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

const pollOpen = computed(() => {
  return event.value?.datePoll?.status === 'open'
})

const dateRanges = computed(() => {
  return event.value?.datePoll?.dateRanges ?? []
})

function handleBack(): void {
  router.push(`/events/${eventId.value}`)
}

function handleAddDateRange(): void {
  if (dateRanges.value.length > 0) {
    const sortedRanges = [...dateRanges.value].sort((a, b) =>
      a.endDate.localeCompare(b.endDate)
    )
    const lastRange = sortedRanges[sortedRanges.length - 1]
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
    await datePollsStore.addDateRange(event.value.id, startDate, endDate)
    showDateRangeModal.value = false
  } catch {
    // Error handled by store
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
        Back to Event
      </button>
    </div>

    <div v-if="!hasSynced" class="text-gray-500 dark:text-gray-400">
      Loading...
    </div>

    <div v-else-if="!event" class="text-gray-500 dark:text-gray-400">
      Event not found
    </div>

    <div
      v-else-if="!event.datePoll || !pollOpen"
      class="py-8 text-center text-gray-500 dark:text-gray-400"
    >
      <p class="mb-2 text-lg font-medium">Voting is closed</p>
      <p>The date poll is no longer accepting votes.</p>
      <button
        type="button"
        class="mt-4 inline-flex items-center gap-2 text-sm text-gray-600 hover:text-gray-900 dark:text-gray-400 dark:hover:text-white"
        @click="handleBack"
      >
        <ArrowLeftIcon class="size-4" />
        Back to Event
      </button>
    </div>

    <div v-else>
      <!-- Event Header -->
      <header class="mb-8">
        <h1
          class="text-3xl font-bold tracking-tight text-gray-900 dark:text-white"
        >
          {{ event.name }}
        </h1>
        <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          Vote on your preferred dates below
        </p>
      </header>

      <!-- Date Ranges with Voting -->
      <section>
        <div class="mb-4 flex items-center justify-between">
          <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
            Date Options
          </h2>
          <button
            v-if="isOwner"
            type="button"
            class="inline-flex items-center gap-2 rounded-md bg-rose-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-rose-500"
            :disabled="datePollsStore.loading"
            @click="handleAddDateRange"
          >
            <PlusIcon class="size-4" />
            Add Date Range
          </button>
        </div>

        <div v-if="dateRanges.length === 0" class="py-8 text-center">
          <p class="mb-4 text-gray-500 dark:text-gray-400">
            No date ranges have been added to this event yet.
          </p>
          <button
            v-if="isOwner"
            type="button"
            class="inline-flex items-center gap-2 rounded-md bg-rose-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-rose-500"
            :disabled="datePollsStore.loading"
            @click="handleAddDateRange"
          >
            <PlusIcon class="size-4" />
            Add Date Range
          </button>
        </div>

        <div v-else class="space-y-4">
          <VotingCard
            v-for="dateRange in dateRanges"
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
