<script setup lang="ts">
import { computed, nextTick, ref } from 'vue'
import { useRoute } from 'vue-router'
import {
  ArrowDownTrayIcon,
  CalendarDaysIcon,
  MapPinIcon,
  PencilIcon,
} from '@heroicons/vue/24/outline'
import AppButton from '@/components/common/AppButton.vue'
import TextButton from '@/components/common/TextButton.vue'
import IconButton from '@/components/common/IconButton.vue'
import { storeToRefs } from 'pinia'
import { useHydratedEvent } from '@/composables/useHydratedEvent'
import { eventHasDates } from '@/utils/event'
import DateRangeDisplay from '@/components/common/DateRangeDisplay.vue'
import BaseModal from '@/components/common/BaseModal.vue'
import StaticMap from '@/components/common/StaticMap.vue'
import LocationInput from '@/components/form/LocationInput.vue'
import { useAuthStore } from '@/stores/auth'
import { useEventsStore } from '@/stores'
import { useObjectPoolStore } from '@/stores/objectPool'
import { generateIcs, downloadIcs } from '@/utils/ics'

const route = useRoute()
const eventId = computed(() => route.params.id as string)
const { event } = useHydratedEvent(eventId)

const authStore = useAuthStore()
const { currentUserId } = storeToRefs(authStore)
const isOwner = computed(() => currentUserId.value === event.value?.userId)

const eventsStore = useEventsStore()
const { loading } = storeToRefs(eventsStore)

const pool = useObjectPoolStore()
const hasExpenses = computed(() => {
  return pool.getAll('expense').some((e) => e.eventId === eventId.value)
})

type EditField = 'name' | 'description' | 'dates' | 'location'
const editField = ref<EditField | null>(null)
const datesBlockedOpen = ref(false)

// Edit state
const editName = ref('')
const editDescription = ref('')
const editStartDate = ref('')
const editEndDate = ref('')
const editLocationName = ref('')
const editLatitude = ref<number | null>(null)
const editLongitude = ref<number | null>(null)

const editInputRef = ref<HTMLInputElement | HTMLTextAreaElement | null>(null)

async function openEdit(field: EditField): Promise<void> {
  if (field === 'dates' && hasExpenses.value) {
    datesBlockedOpen.value = true
    return
  }
  editField.value = field
  switch (field) {
    case 'name':
      editName.value = event.value?.name ?? ''
      break
    case 'description':
      editDescription.value = event.value?.description ?? ''
      break
    case 'dates':
      editStartDate.value = event.value?.startDate ?? ''
      editEndDate.value = event.value?.endDate ?? ''
      break
    case 'location':
      editLocationName.value = event.value?.locationName ?? ''
      editLatitude.value = event.value?.latitude ?? null
      editLongitude.value = event.value?.longitude ?? null
      break
  }
  await nextTick()
  editInputRef.value?.focus()
}

function cancelEdit(): void {
  editField.value = null
}

async function saveEdit(): Promise<void> {
  if (!event.value || loading.value) return

  const data: Record<string, unknown> = {
    name: event.value.name,
    description: event.value.description || undefined,
    startDate: event.value.startDate ?? undefined,
    endDate: event.value.endDate ?? undefined,
    locationName: event.value.locationName || undefined,
    latitude: event.value.latitude ?? undefined,
    longitude: event.value.longitude ?? undefined,
  }

  switch (editField.value) {
    case 'name':
      if (!editName.value.trim()) return
      data.name = editName.value.trim()
      break
    case 'description':
      data.description = editDescription.value.trim() || undefined
      break
    case 'dates':
      data.startDate = editStartDate.value || undefined
      data.endDate = editEndDate.value || undefined
      break
    case 'location':
      data.locationName = editLocationName.value || undefined
      data.latitude = editLatitude.value ?? undefined
      data.longitude = editLongitude.value ?? undefined
      break
  }

  await eventsStore.updateEvent(eventId.value, data)
  editField.value = null
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
  <div v-if="!event" class="text-gray-500 dark:text-stone-400">
    Event not found
  </div>

  <div v-else class="flex lg:gap-8">
    <!-- Left column: event details -->
    <div class="min-w-0 flex-1">
      <!-- Name -->
      <div v-if="editField === 'name'">
        <form class="flex items-center gap-2" @submit.prevent="saveEdit">
          <input
            ref="editInputRef"
            v-model="editName"
            type="text"
            aria-label="Event name"
            placeholder="Event name"
            :maxlength="255"
            :disabled="loading"
            data-testid="edit-name-input"
            class="min-w-0 flex-1 rounded-md bg-gray-100 px-3 py-2 text-2xl font-bold tracking-tight text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:font-normal placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-rose-500 sm:text-3xl dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-stone-500"
            @keyup.escape="cancelEdit"
          />
          <AppButton
            type="submit"
            size="sm"
            :disabled="!editName.trim()"
            :loading="loading"
          >
            Save
          </AppButton>
          <TextButton
            variant="secondary"
            :disabled="loading"
            @click="cancelEdit"
          >
            Cancel
          </TextButton>
        </form>
      </div>
      <div v-else class="group flex items-start gap-2">
        <h1
          class="text-2xl font-bold tracking-tight text-gray-900 sm:text-3xl lg:text-4xl dark:text-white"
        >
          {{ event.name }}
        </h1>
        <IconButton
          v-if="isOwner"
          hover-reveal
          label="Edit name"
          data-testid="edit-name-button"
          class="mt-2 shrink-0"
          @click="openEdit('name')"
        >
          <PencilIcon class="size-5" />
        </IconButton>
      </div>

      <!-- Description -->
      <div v-if="editField === 'description'" class="mt-3">
        <form @submit.prevent="saveEdit">
          <textarea
            ref="editInputRef"
            v-model="editDescription"
            aria-label="Description"
            placeholder="Add a description..."
            rows="3"
            :disabled="loading"
            data-testid="edit-description-input"
            class="w-full rounded-md bg-gray-100 px-3 py-2 text-xl text-gray-600 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-rose-500 dark:bg-white/5 dark:text-stone-300 dark:outline-white/10 dark:placeholder:text-stone-500"
            @keyup.escape="cancelEdit"
          />
          <div class="mt-2 flex items-center gap-2">
            <AppButton type="submit" size="sm" :loading="loading">
              Save
            </AppButton>
            <TextButton
              variant="secondary"
              :disabled="loading"
              @click="cancelEdit"
            >
              Cancel
            </TextButton>
          </div>
        </form>
      </div>
      <div v-else class="group mt-3 flex items-start gap-2">
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
        <IconButton
          v-if="isOwner"
          hover-reveal
          label="Edit description"
          data-testid="edit-description-button"
          class="mt-1 shrink-0"
          @click="openEdit('description')"
        >
          <PencilIcon class="size-4" />
        </IconButton>
      </div>

      <!-- Dates -->
      <div v-if="editField === 'dates'" class="mt-4">
        <form class="flex flex-wrap items-end gap-3" @submit.prevent="saveEdit">
          <div>
            <label
              for="edit-start-date"
              class="mb-1 block text-xs font-medium text-gray-500 dark:text-stone-400"
            >
              Start date
            </label>
            <input
              id="edit-start-date"
              ref="editInputRef"
              v-model="editStartDate"
              type="date"
              :disabled="loading"
              data-testid="edit-start-date-input"
              class="rounded-md bg-gray-100 px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-rose-500 dark:bg-white/5 dark:text-white dark:[color-scheme:dark] dark:outline-white/10"
            />
          </div>
          <div>
            <label
              for="edit-end-date"
              class="mb-1 block text-xs font-medium text-gray-500 dark:text-stone-400"
            >
              End date
            </label>
            <input
              id="edit-end-date"
              v-model="editEndDate"
              type="date"
              :disabled="loading"
              data-testid="edit-end-date-input"
              class="rounded-md bg-gray-100 px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-rose-500 dark:bg-white/5 dark:text-white dark:[color-scheme:dark] dark:outline-white/10"
            />
          </div>
          <AppButton type="submit" size="sm" :loading="loading">
            Save
          </AppButton>
          <TextButton
            variant="secondary"
            :disabled="loading"
            @click="cancelEdit"
          >
            Cancel
          </TextButton>
        </form>
      </div>
      <div v-else class="group mt-4 flex items-center gap-2">
        <div
          v-if="eventHasDates(event)"
          class="flex items-center gap-2 text-gray-500 dark:text-stone-400"
        >
          <CalendarDaysIcon class="size-5 text-amber-600 dark:text-amber-400" />
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
        <IconButton
          v-if="isOwner"
          hover-reveal
          label="Edit dates"
          data-testid="edit-dates-button"
          class="shrink-0"
          @click="openEdit('dates')"
        >
          <PencilIcon class="size-4" />
        </IconButton>
      </div>

      <!-- Location -->
      <div v-if="editField === 'location'" class="mt-4">
        <LocationInput
          v-model="editLocationName"
          aria-label="Location"
          :latitude="editLatitude"
          :longitude="editLongitude"
          :disabled="loading"
          @update:latitude="editLatitude = $event"
          @update:longitude="editLongitude = $event"
        />
        <div class="mt-2 flex items-center gap-2">
          <AppButton size="sm" :loading="loading" @click="saveEdit">
            Save
          </AppButton>
          <TextButton
            variant="secondary"
            :disabled="loading"
            @click="cancelEdit"
          >
            Cancel
          </TextButton>
        </div>
      </div>
      <div v-else class="group mt-4 flex items-center gap-2">
        <div
          v-if="event.locationName"
          class="flex items-center gap-2 text-gray-500 dark:text-stone-400"
        >
          <MapPinIcon
            class="size-5 shrink-0 text-amber-600 dark:text-amber-400"
          />
          <span>{{ event.locationName }}</span>
        </div>
        <div
          v-else-if="isOwner"
          class="flex items-center gap-2 text-gray-400 dark:text-stone-500"
        >
          <MapPinIcon class="size-5" />
          <span class="italic">No location set</span>
        </div>
        <IconButton
          v-if="isOwner"
          hover-reveal
          label="Edit location"
          data-testid="edit-location-button"
          class="shrink-0"
          @click="openEdit('location')"
        >
          <PencilIcon class="size-4" />
        </IconButton>
      </div>

      <TextButton
        v-if="eventHasDates(event)"
        class="mt-4"
        @click="handleDownloadIcs"
      >
        <ArrowDownTrayIcon class="size-5" />
        Add to calendar
      </TextButton>
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

    <BaseModal
      :open="datesBlockedOpen"
      title="Can't change dates"
      @close="datesBlockedOpen = false"
    >
      <p class="text-gray-600 dark:text-stone-300">
        This event has expenses that are tied to the current date range.
        Changing the dates could make those expenses fall outside the event
        period.
      </p>
      <div class="mt-6 flex justify-end">
        <AppButton variant="cyan" @click="datesBlockedOpen = false">
          Got it
        </AppButton>
      </div>
    </BaseModal>
  </div>
</template>
