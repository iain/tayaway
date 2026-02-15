<script setup lang="ts">
import { computed, ref } from 'vue'
import { storeToRefs } from 'pinia'
import { useRouter } from 'vue-router'
import {
  PlusIcon,
  PencilIcon,
  TrashIcon,
  CalendarDaysIcon,
} from '@heroicons/vue/24/outline'
import {
  useEventsStore,
  useAuthStore,
  useObjectPoolStore,
  useNotificationsStore,
} from '@/stores'
import { useCalendar } from '@/composables/useCalendar'
import AddEventModal from '@/components/events/AddEventModal.vue'

const router = useRouter()
const eventsStore = useEventsStore()
const authStore = useAuthStore()
const pool = useObjectPoolStore()
const { loading, error } = storeToRefs(eventsStore)
const { formatDateDisplay } = useCalendar()
const { currentMemberId } = storeToRefs(authStore)

const showModal = ref(false)

const allEvents = computed(() => {
  void pool.version // reactivity dependency
  return pool.getAll('event')
})

const today = computed(() => new Date().toISOString().slice(0, 10))

const upcomingEvents = computed(() =>
  allEvents.value
    .filter((e) => e.startDate && e.startDate >= today.value)
    .sort((a, b) => a.startDate!.localeCompare(b.startDate!))
)

const pastEvents = computed(() =>
  allEvents.value
    .filter((e) => e.startDate && e.startDate < today.value)
    .sort((a, b) => b.startDate!.localeCompare(a.startDate!))
)

const planningEvents = computed(() =>
  allEvents.value
    .filter((e) => !e.startDate)
    .sort(
      (a, b) =>
        new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()
    )
)

const hasEvents = computed(
  () =>
    upcomingEvents.value.length > 0 ||
    pastEvents.value.length > 0 ||
    planningEvents.value.length > 0
)

function isOwner(eventMemberId: string): boolean {
  return currentMemberId.value === eventMemberId
}

function getEventOwner(memberId: string) {
  return pool.get('member', memberId)
}

function getDateRanges(eventId: string) {
  const datePoll = pool.getAll('datePoll').find((dp) => dp.eventId === eventId)
  if (!datePoll) return []
  return pool.getAll('dateRange').filter((dr) => dr.datePollId === datePoll.id)
}

function handleCreate(): void {
  showModal.value = true
}

async function handleModalSave(
  name: string,
  description: string,
  startDate: string | undefined,
  endDate: string | undefined
): Promise<void> {
  try {
    const { eventId, queued } = await eventsStore.createEvent({
      name,
      description: description || undefined,
      startDate,
      endDate,
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

function handleEdit(id: string): void {
  router.push(`/events/${id}/edit`)
}

async function handleDelete(id: string): Promise<void> {
  if (confirm('Are you sure you want to delete this event?')) {
    await eventsStore.deleteEvent(id)
  }
}

function formatEventDates(startDate: string, endDate: string): string {
  if (startDate === endDate) return formatDateDisplay(startDate)
  return `${formatDateDisplay(startDate)} – ${formatDateDisplay(endDate)}`
}

function formatDateRangeSummary(
  ranges: { startDate: string; endDate: string }[]
): string {
  if (ranges.length === 0) return 'No dates'
  if (ranges.length === 1)
    return `${formatDateDisplay(ranges[0]!.startDate)} - ${formatDateDisplay(ranges[0]!.endDate)}`
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

    <div v-if="error" class="text-red-600 dark:text-red-400">
      {{ error }}
    </div>

    <div v-else-if="!hasEvents" class="py-12 text-center">
      <CalendarDaysIcon class="mx-auto size-12 text-gray-400" />
      <h3 class="mt-2 text-sm font-semibold text-gray-900 dark:text-white">
        No events
      </h3>
      <p class="mt-1 text-sm text-gray-500 dark:text-stone-400">
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

    <div v-else data-testid="events-list" class="space-y-8">
      <section v-if="upcomingEvents.length > 0">
        <h2 class="mb-4 text-lg font-medium text-gray-900 dark:text-white">
          Upcoming
        </h2>
        <ul class="space-y-4">
          <li
            v-for="event in upcomingEvents"
            :key="event.id"
            :data-testid="`event-item-${event.id}`"
            class="cursor-pointer overflow-hidden rounded-lg bg-white shadow transition-all hover:ring-2 hover:ring-rose-500 dark:bg-stone-800"
            @click="handleView(event.id)"
          >
            <div class="px-4 py-5 sm:px-6">
              <div class="flex items-center justify-between">
                <div class="min-w-0 flex-1">
                  <h3
                    data-testid="event-name"
                    class="truncate text-lg font-semibold text-gray-900 dark:text-white"
                  >
                    {{ event.name }}
                  </h3>
                  <p
                    v-if="event.description"
                    class="mt-1 text-sm text-gray-500 dark:text-stone-400"
                  >
                    {{ event.description }}
                  </p>
                  <div
                    class="mt-2 flex items-center gap-3 text-sm text-gray-600 dark:text-stone-300"
                  >
                    <span class="inline-flex items-center gap-1">
                      <CalendarDaysIcon class="size-4" />
                      {{ formatEventDates(event.startDate!, event.endDate!) }}
                    </span>
                    <span class="text-gray-400 dark:text-stone-500"
                      >by
                      {{
                        getEventOwner(event.memberId)?.name ||
                        getEventOwner(event.memberId)?.email ||
                        'Unknown'
                      }}</span
                    >
                  </div>
                </div>
                <div
                  v-if="isOwner(event.memberId)"
                  class="ml-4 flex items-center gap-2"
                >
                  <button
                    type="button"
                    class="p-2 text-gray-400 hover:text-cyan-600 dark:hover:text-cyan-400"
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
      </section>

      <section v-if="planningEvents.length > 0">
        <h2 class="mb-4 text-lg font-medium text-gray-900 dark:text-white">
          Planning
        </h2>
        <ul class="space-y-4">
          <li
            v-for="event in planningEvents"
            :key="event.id"
            :data-testid="`event-item-${event.id}`"
            class="cursor-pointer overflow-hidden rounded-lg bg-white shadow transition-all hover:ring-2 hover:ring-rose-500 dark:bg-stone-800"
            @click="handleView(event.id)"
          >
            <div class="px-4 py-5 sm:px-6">
              <div class="flex items-center justify-between">
                <div class="min-w-0 flex-1">
                  <h3
                    data-testid="event-name"
                    class="truncate text-lg font-semibold text-gray-900 dark:text-white"
                  >
                    {{ event.name }}
                  </h3>
                  <p
                    v-if="event.description"
                    class="mt-1 text-sm text-gray-500 dark:text-stone-400"
                  >
                    {{ event.description }}
                  </p>
                  <div
                    class="mt-2 flex items-center gap-3 text-sm text-gray-600 dark:text-stone-300"
                  >
                    <span>{{
                      formatDateRangeSummary(getDateRanges(event.id))
                    }}</span>
                    <span class="text-gray-400 dark:text-stone-500"
                      >by
                      {{
                        getEventOwner(event.memberId)?.name ||
                        getEventOwner(event.memberId)?.email ||
                        'Unknown'
                      }}</span
                    >
                  </div>
                </div>
                <div
                  v-if="isOwner(event.memberId)"
                  class="ml-4 flex items-center gap-2"
                >
                  <button
                    type="button"
                    class="p-2 text-gray-400 hover:text-cyan-600 dark:hover:text-cyan-400"
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
      </section>

      <section v-if="pastEvents.length > 0">
        <h2 class="mb-4 text-lg font-medium text-gray-900 dark:text-white">
          Past
        </h2>
        <ul class="space-y-4">
          <li
            v-for="event in pastEvents"
            :key="event.id"
            :data-testid="`event-item-${event.id}`"
            class="cursor-pointer overflow-hidden rounded-lg bg-white shadow transition-all hover:ring-2 hover:ring-rose-500 dark:bg-stone-800"
            @click="handleView(event.id)"
          >
            <div class="px-4 py-5 sm:px-6">
              <div class="flex items-center justify-between">
                <div class="min-w-0 flex-1">
                  <h3
                    data-testid="event-name"
                    class="truncate text-lg font-semibold text-gray-900 dark:text-white"
                  >
                    {{ event.name }}
                  </h3>
                  <p
                    v-if="event.description"
                    class="mt-1 text-sm text-gray-500 dark:text-stone-400"
                  >
                    {{ event.description }}
                  </p>
                  <div
                    class="mt-2 flex items-center gap-3 text-sm text-gray-600 dark:text-stone-300"
                  >
                    <span class="inline-flex items-center gap-1">
                      <CalendarDaysIcon class="size-4" />
                      {{ formatEventDates(event.startDate!, event.endDate!) }}
                    </span>
                    <span class="text-gray-400 dark:text-stone-500"
                      >by
                      {{
                        getEventOwner(event.memberId)?.name ||
                        getEventOwner(event.memberId)?.email ||
                        'Unknown'
                      }}</span
                    >
                  </div>
                </div>
                <div
                  v-if="isOwner(event.memberId)"
                  class="ml-4 flex items-center gap-2"
                >
                  <button
                    type="button"
                    class="p-2 text-gray-400 hover:text-cyan-600 dark:hover:text-cyan-400"
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
