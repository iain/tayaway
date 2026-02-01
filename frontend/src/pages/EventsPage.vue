<script setup lang="ts">
import { onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { PlusIcon, PencilIcon, TrashIcon, CalendarDaysIcon } from '@heroicons/vue/24/outline'
import { useEvents } from '@/composables/useEvents'
import { useCalendar } from '@/composables/useCalendar'

const router = useRouter()
const { events, loading, error, fetchEvents, deleteEvent } = useEvents()
const { formatDateDisplay } = useCalendar()

onMounted(() => {
  fetchEvents()
})

function handleCreate(): void {
  router.push('/events/new')
}

function handleEdit(id: string): void {
  router.push(`/events/${id}/edit`)
}

async function handleDelete(id: string): Promise<void> {
  if (confirm('Are you sure you want to delete this event?')) {
    await deleteEvent(id)
  }
}

function formatDateRangeSummary(ranges: { start_date: string; end_date: string }[]): string {
  if (ranges.length === 0) return 'No dates'
  if (ranges.length === 1) return `${formatDateDisplay(ranges[0].start_date)} - ${formatDateDisplay(ranges[0].end_date)}`
  return `${ranges.length} date ranges`
}
</script>

<template>
  <div>
    <header class="mb-6 flex items-center justify-between">
      <h1 class="text-3xl font-bold tracking-tight text-gray-900 dark:text-white">
        Events
      </h1>
      <button
        type="button"
        class="inline-flex items-center gap-2 rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500"
        @click="handleCreate"
      >
        <PlusIcon class="size-5" />
        New Event
      </button>
    </header>

    <div
      v-if="loading"
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
          class="inline-flex items-center gap-2 rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500"
          @click="handleCreate"
        >
          <PlusIcon class="size-5" />
          New Event
        </button>
      </div>
    </div>

    <ul
      v-else
      class="divide-y divide-gray-200 dark:divide-gray-700"
    >
      <li
        v-for="event in events"
        :key="event.id"
        class="bg-white dark:bg-gray-800 shadow rounded-lg mb-4 overflow-hidden"
      >
        <div class="px-4 py-5 sm:px-6">
          <div class="flex items-center justify-between">
            <div class="min-w-0 flex-1">
              <h2 class="text-lg font-semibold text-gray-900 dark:text-white truncate">
                {{ event.name }}
              </h2>
              <p
                v-if="event.description"
                class="mt-1 text-sm text-gray-500 dark:text-gray-400"
              >
                {{ event.description }}
              </p>
              <p class="mt-2 text-sm text-gray-600 dark:text-gray-300">
                {{ formatDateRangeSummary(event.date_ranges) }}
              </p>
            </div>
            <div class="ml-4 flex items-center gap-2">
              <button
                type="button"
                class="p-2 text-gray-400 hover:text-indigo-600 dark:hover:text-indigo-400"
                @click="handleEdit(event.id)"
              >
                <PencilIcon class="size-5" />
                <span class="sr-only">Edit</span>
              </button>
              <button
                type="button"
                class="p-2 text-gray-400 hover:text-red-600 dark:hover:text-red-400"
                @click="handleDelete(event.id)"
              >
                <TrashIcon class="size-5" />
                <span class="sr-only">Delete</span>
              </button>
            </div>
          </div>
        </div>
      </li>
    </ul>
  </div>
</template>
