<script setup lang="ts">
import { computed, ref } from 'vue'
import { storeToRefs } from 'pinia'
import { useRouter } from 'vue-router'
import { PlusIcon, PencilIcon, TrashIcon, CalendarDaysIcon } from '@heroicons/vue/24/outline'
import { useEventsStore, useAuthStore, useObjectPoolStore, useWebSocketStore } from '@/stores'
import { useCalendar } from '@/composables/useCalendar'
import AddEventModal from '@/components/events/AddEventModal.vue'

const router = useRouter()
const eventsStore = useEventsStore()
const authStore = useAuthStore()
const pool = useObjectPoolStore()
const wsStore = useWebSocketStore()
const { loading, error } = storeToRefs(eventsStore)
const { hasSynced } = storeToRefs(wsStore)
const { formatDateDisplay } = useCalendar()
const { user } = storeToRefs(authStore)

const showModal = ref(false)

// Get events from pool, sorted by createdAt
const events = computed(() => {
  void pool.version // reactivity dependency
  return pool.getAll('event').sort((a, b) =>
    new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime()
  )
})

function isOwner(eventUserId: string): boolean {
  return user.value?.id === eventUserId
}

function getEventOwner(userId: string) {
  return pool.get('user', userId)
}

function getDateRanges(dateRangeIds: string[]) {
  return pool.getMany('dateRange', dateRangeIds)
}

function handleCreate(): void {
  showModal.value = true
}

async function handleModalSave(name: string, description: string): Promise<void> {
  try {
    const eventId = await eventsStore.createEvent({
      name,
      description: description || undefined,
    })
    showModal.value = false
    router.push(`/events/${eventId}`)
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

function handleEdit(id: string): void {
  router.push(`/events/${id}/edit`)
}

async function handleDelete(id: string): Promise<void> {
  if (confirm('Are you sure you want to delete this event?')) {
    await eventsStore.deleteEvent(id)
  }
}

function formatDateRangeSummary(ranges: { startDate: string; endDate: string }[]): string {
  if (ranges.length === 0) return 'No dates'
  if (ranges.length === 1) return `${formatDateDisplay(ranges[0].startDate)} - ${formatDateDisplay(ranges[0].endDate)}`
  return `${ranges.length} date ranges`
}
</script>

<template>
  <div>
    <header class="mb-6 flex items-center justify-between">
      <h1
        data-testid="page-title"
        class="text-3xl font-bold tracking-tight text-gray-900 dark:text-white"
      >
        Events
      </h1>
      <button
        type="button"
        data-testid="new-event-button"
        class="inline-flex items-center gap-2 rounded-md bg-rose-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-rose-500"
        @click="handleCreate"
      >
        <PlusIcon class="size-5" />
        New Event
      </button>
    </header>

    <div
      v-if="!hasSynced"
      class="text-gray-500 dark:text-gray-400"
    >
      Loading events...
    </div>

    <div
      v-else-if="error"
      class="text-red-600 dark:text-red-400"
    >
      {{ error }}
    </div>

    <div
      v-else-if="events.length === 0"
      class="text-center py-12"
    >
      <CalendarDaysIcon class="mx-auto size-12 text-gray-400" />
      <h3 class="mt-2 text-sm font-semibold text-gray-900 dark:text-white">
        No events
      </h3>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        Get started by creating a new event.
      </p>
      <div class="mt-6">
        <button
          type="button"
          class="inline-flex items-center gap-2 rounded-md bg-rose-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-rose-500"
          @click="handleCreate"
        >
          <PlusIcon class="size-5" />
          New Event
        </button>
      </div>
    </div>

    <ul
      v-else
      data-testid="events-list"
      class="divide-y divide-gray-200 dark:divide-gray-700"
    >
      <li
        v-for="event in events"
        :key="event.id"
        :data-testid="`event-item-${event.id}`"
        class="bg-white dark:bg-gray-800 shadow rounded-lg mb-4 overflow-hidden hover:ring-2 hover:ring-rose-500 transition-all cursor-pointer"
        @click="handleView(event.id)"
      >
        <div class="px-4 py-5 sm:px-6">
          <div class="flex items-center justify-between">
            <div class="min-w-0 flex-1">
              <h2
                data-testid="event-name"
                class="text-lg font-semibold text-gray-900 dark:text-white truncate"
              >
                {{ event.name }}
              </h2>
              <p
                v-if="event.description"
                class="mt-1 text-sm text-gray-500 dark:text-gray-400"
              >
                {{ event.description }}
              </p>
              <div class="mt-2 flex items-center gap-3 text-sm text-gray-600 dark:text-gray-300">
                <span>{{ formatDateRangeSummary(getDateRanges(event.dateRangeIds)) }}</span>
                <span class="text-gray-400 dark:text-gray-500">by {{ getEventOwner(event.userId)?.name || getEventOwner(event.userId)?.email || 'Unknown' }}</span>
              </div>
            </div>
            <div
              v-if="isOwner(event.userId)"
              class="ml-4 flex items-center gap-2"
            >
              <button
                type="button"
                class="p-2 text-gray-400 hover:text-rose-600 dark:hover:text-rose-400"
                @click.stop="handleEdit(event.id)"
              >
                <PencilIcon class="size-5" />
                <span class="sr-only">Edit</span>
              </button>
              <button
                type="button"
                class="p-2 text-gray-400 hover:text-red-600 dark:hover:text-red-400"
                @click.stop="handleDelete(event.id)"
              >
                <TrashIcon class="size-5" />
                <span class="sr-only">Delete</span>
              </button>
            </div>
          </div>
        </div>
      </li>
    </ul>

    <AddEventModal
      :open="showModal"
      :loading="loading"
      @save="handleModalSave"
      @close="handleModalClose"
    />
  </div>
</template>
