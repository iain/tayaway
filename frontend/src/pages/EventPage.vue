<script setup lang="ts">
import { computed, ref } from 'vue'
import { useRoute } from 'vue-router'
import {
  ArrowDownTrayIcon,
  CalendarDaysIcon,
  MapPinIcon,
  PencilIcon,
} from '@heroicons/vue/24/outline'
import { storeToRefs } from 'pinia'
import { useHydratedEvent } from '@/composables/useHydratedEvent'
import { eventHasDates } from '@/utils/event'
import DateRangeDisplay from '@/components/common/DateRangeDisplay.vue'
import EditEventModal from '@/components/events/EditEventModal.vue'
import StaticMap from '@/components/common/StaticMap.vue'
import { useAuthStore } from '@/stores/auth'
import { useEventsStore } from '@/stores'
import { generateIcs, downloadIcs } from '@/utils/ics'

const route = useRoute()
const eventId = computed(() => route.params.id as string)
const { event } = useHydratedEvent(eventId)

const authStore = useAuthStore()
const { currentUserId } = storeToRefs(authStore)
const isOwner = computed(() => currentUserId.value === event.value?.userId)

const eventsStore = useEventsStore()
const { loading } = storeToRefs(eventsStore)

type EditField = 'name' | 'description' | 'dates' | 'location'
const editField = ref<EditField>('name')
const modalOpen = ref(false)

function openEdit(field: EditField): void {
  editField.value = field
  modalOpen.value = true
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
</script>

<template>
  <div v-if="!event" class="text-gray-500 dark:text-stone-400">
    Event not found
  </div>

  <div v-else class="flex gap-8">
    <!-- Left column: event details -->
    <div class="min-w-0 flex-1">
      <div class="group flex items-start gap-2">
        <h1
          class="text-4xl font-bold tracking-tight text-gray-900 dark:text-white"
        >
          {{ event.name }}
        </h1>
        <button
          v-if="isOwner"
          type="button"
          data-testid="edit-name-button"
          class="mt-2 shrink-0 rounded p-0.5 text-gray-400 opacity-0 transition-opacity group-hover:opacity-100 hover:text-gray-600 dark:text-stone-500 dark:hover:text-stone-300"
          @click="openEdit('name')"
        >
          <PencilIcon class="size-5" />
        </button>
      </div>

      <div class="group mt-3 flex items-start gap-2">
        <p
          v-if="event.description"
          class="text-xl text-gray-600 dark:text-stone-300"
        >
          {{ event.description }}
        </p>
        <p
          v-else-if="isOwner"
          class="text-xl text-gray-400 italic dark:text-stone-500"
        >
          No description
        </p>
        <button
          v-if="isOwner"
          type="button"
          data-testid="edit-description-button"
          class="mt-1 shrink-0 rounded p-0.5 text-gray-400 opacity-0 transition-opacity group-hover:opacity-100 hover:text-gray-600 dark:text-stone-500 dark:hover:text-stone-300"
          @click="openEdit('description')"
        >
          <PencilIcon class="size-4" />
        </button>
      </div>

      <div class="group mt-4 flex items-center gap-2">
        <div
          v-if="eventHasDates(event)"
          class="flex items-center gap-2 text-gray-500 dark:text-stone-400"
        >
          <CalendarDaysIcon class="size-5" />
          <DateRangeDisplay
            :start-date="event.startDate!"
            :end-date="event.endDate!"
          />
        </div>
        <div
          v-else-if="isOwner"
          class="flex items-center gap-2 text-gray-400 dark:text-stone-500"
        >
          <CalendarDaysIcon class="size-5" />
          <span class="italic">No dates set</span>
        </div>
        <button
          v-if="isOwner"
          type="button"
          data-testid="edit-dates-button"
          class="shrink-0 rounded p-0.5 text-gray-400 opacity-0 transition-opacity group-hover:opacity-100 hover:text-gray-600 dark:text-stone-500 dark:hover:text-stone-300"
          @click="openEdit('dates')"
        >
          <PencilIcon class="size-4" />
        </button>
      </div>

      <div class="group mt-4 flex items-center gap-2">
        <div
          v-if="event.locationName"
          class="flex items-center gap-2 text-gray-500 dark:text-stone-400"
        >
          <MapPinIcon class="size-5 shrink-0" />
          <span>{{ event.locationName }}</span>
        </div>
        <div
          v-else-if="isOwner"
          class="flex items-center gap-2 text-gray-400 dark:text-stone-500"
        >
          <MapPinIcon class="size-5" />
          <span class="italic">No location set</span>
        </div>
        <button
          v-if="isOwner"
          type="button"
          data-testid="edit-location-button"
          class="shrink-0 rounded p-0.5 text-gray-400 opacity-0 transition-opacity group-hover:opacity-100 hover:text-gray-600 dark:text-stone-500 dark:hover:text-stone-300"
          @click="openEdit('location')"
        >
          <PencilIcon class="size-4" />
        </button>
      </div>

      <button
        v-if="eventHasDates(event)"
        type="button"
        class="mt-4 inline-flex items-center gap-2 text-cyan-600 hover:text-cyan-700 dark:text-cyan-400 dark:hover:text-cyan-300"
        @click="handleDownloadIcs"
      >
        <ArrowDownTrayIcon class="size-5" />
        Add to calendar
      </button>
    </div>

    <!-- Right column: map -->
    <div
      v-if="event.latitude != null && event.longitude != null"
      class="hidden w-1/2 shrink-0 lg:block"
    >
      <div class="sticky top-4">
        <StaticMap
          :latitude="event.latitude"
          :longitude="event.longitude"
          class="h-72 rounded-xl shadow-sm"
        />
      </div>
    </div>

    <EditEventModal
      :open="modalOpen"
      :field="editField"
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
  </div>
</template>
