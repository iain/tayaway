<script setup lang="ts">
import { computed, nextTick, ref } from 'vue'
import { useRoute } from 'vue-router'
import { useRouter } from 'vue-router'
import {
  ArrowDownTrayIcon,
  CalendarDaysIcon,
  ChevronLeftIcon,
  ChevronRightIcon,
  GlobeAltIcon,
  MapPinIcon,
  PencilIcon,
  TrashIcon,
} from '@heroicons/vue/24/outline'
import AppButton from '@/components/common/AppButton.vue'
import TextButton from '@/components/common/TextButton.vue'
import IconButton from '@/components/common/IconButton.vue'
import CalendarMonth from '@/components/calendar/CalendarMonth.vue'
import { storeToRefs } from 'pinia'
import { useHydratedEvent } from '@/composables/useHydratedEvent'
import { eventHasDates } from '@/utils/event'
import DateRangeDisplay from '@/components/common/DateRangeDisplay.vue'
import BaseModal from '@/components/common/BaseModal.vue'
import StaticMap from '@/components/common/StaticMap.vue'
import LocationInput from '@/components/form/LocationInput.vue'
import TimezoneSelect from '@/components/form/TimezoneSelect.vue'
import { useEventsStore, useWorkspaceStore } from '@/stores'
import { timezoneForCoordinates, effectiveEventZone } from '@/utils/geoTimezone'
import type { UpdateEventRequest } from '@/types'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useCalendar } from '@/composables/useCalendar'
import { generateIcs, downloadIcs } from '@/utils/ics'
import { can } from '@/composables/usePermission'
import { TEXT_LIMITS } from '@/constants/limits'

const route = useRoute()
const router = useRouter()
const eventId = computed(() => route.params.id as string)
const { event } = useHydratedEvent(eventId)

const canEdit = computed(() => can(event.value?.permissions, 'edit'))
const canDelete = computed(() => can(event.value?.permissions, 'delete'))

const eventsStore = useEventsStore()
const { loading } = storeToRefs(eventsStore)

const pool = useObjectPoolStore()
const hasExpenses = computed(() => {
  return pool.getAll('expense').some((e) => e.eventId === eventId.value)
})

const mapsUrl = computed(() => {
  if (event.value?.latitude == null || event.value?.longitude == null)
    return null
  return `https://maps.google.com/?q=${event.value.latitude},${event.value.longitude}`
})

type EditField = 'name' | 'description' | 'dates' | 'location' | 'timezone'
const editField = ref<EditField | null>(null)
const datesBlockedOpen = ref(false)
const showRsvpWarning = ref(false)

const eventRsvps = computed(() =>
  pool.getAll('rsvp').filter((r) => r.eventId === eventId.value)
)

const eventAttendances = computed(() =>
  pool.getAll('attendance').filter((a) => a.eventId === eventId.value)
)

// Rows a date change would reset: any answered attendance (member or
// guest). Legacy rsvp rows from stale clients count too.
const answeredCount = computed(() => {
  const answered = eventAttendances.value.filter((a) => a.status !== 'pending')
  const mirrored = new Set(answered.map((a) => a.userId))
  const legacyOnly = eventRsvps.value.filter((r) => !mirrored.has(r.userId))
  return answered.length + legacyOnly.length
})

const datesActuallyChanged = computed(() => {
  if (!event.value) return false
  return (
    editStartDate.value !== (event.value.startDate ?? null) ||
    editEndDate.value !== (event.value.endDate ?? null)
  )
})

// Delete event
const showDeleteConfirm = ref(false)
const deleting = ref(false)

const eventVoteCount = computed(() => {
  const dateRangeIds = new Set(
    pool
      .getAll('dateRange')
      .filter((dr) => {
        const poll = pool.getAll('datePoll').find((p) => p.id === dr.datePollId)
        return poll?.eventId === eventId.value
      })
      .map((dr) => dr.id)
  )
  return pool.getAll('vote').filter((v) => dateRangeIds.has(v.dateRangeId))
    .length
})

const hasChoreRoster = computed(() =>
  pool.getAll('choreRoster').some((r) => r.eventId === eventId.value)
)

const deleteSummary = computed(() => {
  const parts: string[] = []
  const rsvpCount = eventRsvps.value.length
  const voteCount = eventVoteCount.value
  if (rsvpCount > 0)
    parts.push(`${rsvpCount} ${rsvpCount === 1 ? 'RSVP' : 'RSVPs'}`)
  if (voteCount > 0)
    parts.push(`${voteCount} ${voteCount === 1 ? 'vote' : 'votes'}`)
  if (hasChoreRoster.value) parts.push('the chore roster')
  return parts
})

async function handleDeleteEvent(): Promise<void> {
  if (deleting.value) return
  deleting.value = true
  try {
    await eventsStore.deleteEvent(eventId.value)
    showDeleteConfirm.value = false
    router.push('/events')
  } catch {
    // Error handled by store
  } finally {
    deleting.value = false
  }
}

const { formatDateDisplay } = useCalendar()

// Edit state
const editName = ref('')
const editDescription = ref('')
const editStartDate = ref<string | null>(null)
const editEndDate = ref<string | null>(null)
const hoverDate = ref<string | null>(null)
const editLocationName = ref('')
const editLatitude = ref<number | null>(null)
const editLongitude = ref<number | null>(null)
const editTimezone = ref('')

// The zone the event would derive from its current location, shown as the hint
// behind the "Automatic" option.
const workspaceStore = useWorkspaceStore()
const editEffectiveTimezone = computed(() =>
  effectiveEventZone(
    event.value?.latitude,
    event.value?.longitude,
    workspaceStore.currentWorkspace?.timezone
  )
)

const editInputRef = ref<HTMLInputElement | HTMLTextAreaElement | null>(null)

// Calendar navigation for date editing
const calYear = ref(new Date().getFullYear())
const calMonth = ref(new Date().getMonth())

const rightYear = computed(() =>
  calMonth.value === 11 ? calYear.value + 1 : calYear.value
)
const rightMonth = computed(() => (calMonth.value + 1) % 12)

function calPrev(): void {
  if (calMonth.value === 0) {
    calMonth.value = 11
    calYear.value--
  } else {
    calMonth.value--
  }
}

function calNext(): void {
  if (calMonth.value === 11) {
    calMonth.value = 0
    calYear.value++
  } else {
    calMonth.value++
  }
}

function handleDateSelect(dateString: string): void {
  if (!editStartDate.value || editEndDate.value) {
    editStartDate.value = dateString
    editEndDate.value = null
  } else {
    let start = editStartDate.value
    let end = dateString
    if (dateString < editStartDate.value) {
      start = dateString
      end = editStartDate.value
    }
    editStartDate.value = start
    editEndDate.value = end
  }
}

const dateSelectionText = computed(() => {
  if (editStartDate.value && editEndDate.value) {
    return `${formatDateDisplay(editStartDate.value)} — ${formatDateDisplay(editEndDate.value)}`
  }
  if (editStartDate.value) {
    return `${formatDateDisplay(editStartDate.value)} — pick end date`
  }
  return 'Pick start date'
})

const canSaveDates = computed(
  () => !!editStartDate.value && !!editEndDate.value
)

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
      editStartDate.value = event.value?.startDate ?? null
      editEndDate.value = event.value?.endDate ?? null
      hoverDate.value = null
      if (event.value?.startDate) {
        const [y, m] = event.value.startDate.split('-').map(Number) as [
          number,
          number,
        ]
        calYear.value = y
        calMonth.value = m - 1
      } else {
        calYear.value = new Date().getFullYear()
        calMonth.value = new Date().getMonth()
      }
      break
    case 'location':
      editLocationName.value = event.value?.locationName ?? ''
      editLatitude.value = event.value?.latitude ?? null
      editLongitude.value = event.value?.longitude ?? null
      break
    case 'timezone':
      editTimezone.value = event.value?.timezone ?? ''
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

  // When changing dates, warn if RSVPs exist and dates actually changed
  if (
    editField.value === 'dates' &&
    datesActuallyChanged.value &&
    answeredCount.value > 0
  ) {
    showRsvpWarning.value = true
    return
  }

  await commitEdit()
}

async function commitEdit(): Promise<void> {
  if (!event.value || loading.value) return

  const data: UpdateEventRequest = {
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
      // A new location moves the zone with it (no change if we can't derive one).
      data.timezone =
        timezoneForCoordinates(editLatitude.value, editLongitude.value) ??
        undefined
      break
    case 'timezone':
      // Explicit pick, or "Automatic" => re-derive from the current location.
      data.timezone =
        editTimezone.value ||
        timezoneForCoordinates(event.value.latitude, event.value.longitude) ||
        undefined
      break
  }

  // A date change resets the answers server-side (Events::Update,
  // doc/attendances.md phase 6): attendances revert to pending
  // transactionally and broadcast per row — the modal above is only the
  // user's confirmation.
  await eventsStore.updateEvent(eventId.value, data)
  showRsvpWarning.value = false
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
  <div v-if="!event" class="text-ink-muted">Event not found</div>

  <div v-else class="flex flex-col lg:flex-row lg:gap-8">
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
            :maxlength="TEXT_LIMITS.name"
            :disabled="loading"
            data-testid="edit-name-input"
            class="bg-surface-sunken text-ink outline-line placeholder:text-ink-placeholder focus:outline-focus min-w-0 flex-1 rounded-md px-3 py-2 text-2xl font-bold tracking-tight outline-1 -outline-offset-1 placeholder:font-normal focus:outline-2 focus:outline-offset-2 sm:text-3xl"
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
      <div v-else class="group flex items-start gap-0.5">
        <h1
          class="text-ink text-2xl font-bold tracking-tight sm:text-3xl lg:text-4xl"
        >
          {{ event.name }}
        </h1>
        <IconButton
          v-if="canEdit"
          hover-reveal
          label="Edit name"
          data-testid="edit-name-button"
          class="-mt-1.5 shrink-0 sm:mt-2"
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
            :maxlength="TEXT_LIMITS.longText"
            :disabled="loading"
            data-testid="edit-description-input"
            class="bg-surface-sunken outline-line placeholder:text-ink-placeholder focus:outline-focus text-ink-muted w-full rounded-md px-3 py-2 text-xl outline-1 -outline-offset-1 focus:outline-2 focus:outline-offset-2"
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
      <div v-else class="group mt-3 flex items-start gap-0.5">
        <p v-if="event.description" class="text-ink-muted text-xl">
          {{ event.description }}
        </p>
        <p v-else-if="canEdit" class="text-ink-muted text-xl italic">
          No description
        </p>
        <IconButton
          v-if="canEdit"
          hover-reveal
          label="Edit description"
          data-testid="edit-description-button"
          class="-mt-2 shrink-0 sm:mt-1"
          @click="openEdit('description')"
        >
          <PencilIcon class="size-4" />
        </IconButton>
      </div>

      <!-- Dates -->
      <BaseModal
        :open="editField === 'dates'"
        title="Event dates"
        size="2xl"
        @close="cancelEdit"
      >
        <div class="text-ink-muted mb-4 text-sm">
          {{ dateSelectionText }}
        </div>

        <div class="mb-4 flex items-center justify-between">
          <IconButton label="Previous month" @click="calPrev">
            <ChevronLeftIcon class="size-5" />
          </IconButton>
          <IconButton label="Next month" @click="calNext">
            <ChevronRightIcon class="size-5" />
          </IconButton>
        </div>

        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 sm:gap-8">
          <CalendarMonth
            :year="calYear"
            :month="calMonth"
            :selected-start="editStartDate"
            :selected-end="editEndDate"
            :hover-date="hoverDate"
            @select="handleDateSelect"
            @hover="hoverDate = $event"
          />
          <CalendarMonth
            :year="rightYear"
            :month="rightMonth"
            :selected-start="editStartDate"
            :selected-end="editEndDate"
            :hover-date="hoverDate"
            @select="handleDateSelect"
            @hover="hoverDate = $event"
          />
        </div>

        <div class="mt-6 flex items-center justify-end gap-3">
          <TextButton variant="secondary" @click="cancelEdit">
            Cancel
          </TextButton>
          <AppButton
            :disabled="!canSaveDates"
            :loading="loading"
            @click="saveEdit"
          >
            Save
          </AppButton>
        </div>
      </BaseModal>
      <div class="group mt-4 flex items-center gap-0.5">
        <div
          v-if="eventHasDates(event)"
          class="text-ink-muted flex items-center gap-2"
        >
          <CalendarDaysIcon class="size-5 text-amber-600 dark:text-amber-400" />
          <DateRangeDisplay
            :start-date="event.startDate!"
            :end-date="event.endDate!"
          />
        </div>
        <div v-else-if="canEdit" class="text-ink-muted flex items-center gap-2">
          <CalendarDaysIcon class="size-5" />
          <span class="italic">No dates set</span>
        </div>
        <IconButton
          v-if="canEdit"
          hover-reveal
          label="Edit dates"
          data-testid="edit-dates-button"
          class="-my-2 shrink-0 sm:my-0"
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
          :maxlength="TEXT_LIMITS.name"
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
      <div v-else class="group mt-4 flex items-center gap-0.5">
        <component
          :is="mapsUrl ? 'a' : 'div'"
          v-if="event.locationName"
          :href="mapsUrl ?? undefined"
          :target="mapsUrl ? '_blank' : undefined"
          :rel="mapsUrl ? 'noopener noreferrer' : undefined"
          class="text-ink-muted flex items-center gap-2"
          :class="
            mapsUrl &&
            'focus-visible:outline-focus rounded hover:text-amber-700 focus-visible:outline-2 focus-visible:outline-offset-2 dark:hover:text-amber-400'
          "
        >
          <MapPinIcon
            class="size-5 shrink-0 text-amber-600 dark:text-amber-400"
          />
          <span>{{ event.locationName }}</span>
        </component>
        <div v-else-if="canEdit" class="text-ink-muted flex items-center gap-2">
          <MapPinIcon class="size-5" />
          <span class="italic">No location set</span>
        </div>
        <IconButton
          v-if="canEdit"
          hover-reveal
          label="Edit location"
          data-testid="edit-location-button"
          class="-my-2 shrink-0 sm:my-0"
          @click="openEdit('location')"
        >
          <PencilIcon class="size-4" />
        </IconButton>
      </div>

      <!-- Time zone -->
      <div v-if="editField === 'timezone'" class="mt-4">
        <TimezoneSelect
          id="event-edit-timezone"
          v-model="editTimezone"
          label="Time zone"
          auto-label="Automatic (from location)"
          :effective-zone="editEffectiveTimezone"
          :disabled="loading"
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
      <div v-else class="group mt-4 flex items-center gap-0.5">
        <div class="text-ink-muted flex items-center gap-2">
          <GlobeAltIcon
            class="size-5 shrink-0 text-amber-600 dark:text-amber-400"
          />
          <span>{{ event.timezone }}</span>
        </div>
        <IconButton
          v-if="canEdit"
          hover-reveal
          label="Edit time zone"
          data-testid="edit-timezone-button"
          class="-my-2 shrink-0 sm:my-0"
          @click="openEdit('timezone')"
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

    <!-- Map -->
    <div
      v-if="event.latitude != null && event.longitude != null"
      class="mt-6 lg:mt-0 lg:w-1/2 lg:shrink-0"
    >
      <div class="lg:sticky lg:top-4">
        <a
          :href="mapsUrl!"
          target="_blank"
          rel="noopener noreferrer"
          class="block"
        >
          <StaticMap
            :latitude="event.latitude"
            :longitude="event.longitude"
            class="h-48 rounded-xl shadow-sm transition-shadow hover:shadow-md sm:h-60 lg:h-72"
          />
        </a>
      </div>
    </div>
  </div>

  <!-- Delete (owner only, below the two-column layout) -->
  <div v-if="event && canEdit" class="border-line mt-12 border-t pt-6">
    <TextButton variant="danger" @click="showDeleteConfirm = true">
      <TrashIcon class="size-4" />
      Delete event
    </TextButton>
  </div>

  <template v-if="event">
    <BaseModal
      :open="datesBlockedOpen"
      title="Can't change dates"
      @close="datesBlockedOpen = false"
    >
      <p class="text-ink-muted">
        This event has expenses that are tied to the current date range.
        Changing the dates could make those expenses fall outside the event
        period.
      </p>
      <div class="mt-6 flex justify-end">
        <AppButton variant="secondary" @click="datesBlockedOpen = false">
          Got it
        </AppButton>
      </div>
    </BaseModal>

    <BaseModal
      :open="showRsvpWarning"
      title="Reset RSVPs?"
      size="sm"
      @close="showRsvpWarning = false"
    >
      <p class="text-ink-muted text-sm">
        {{ answeredCount }}
        {{ answeredCount === 1 ? 'person has' : 'people have' }} already
        responded. Changing the dates keeps everyone on the list but clears
        their day picks, so they can re-confirm for the new dates.
      </p>
      <div class="mt-6 flex justify-end gap-3">
        <TextButton variant="secondary" @click="showRsvpWarning = false">
          Cancel
        </TextButton>
        <AppButton :loading="loading" @click="commitEdit">
          Change dates &amp; reset responses
        </AppButton>
      </div>
    </BaseModal>

    <BaseModal
      :open="showDeleteConfirm"
      title="Delete event"
      size="sm"
      @close="showDeleteConfirm = false"
    >
      <template v-if="!canDelete">
        <p class="text-ink-muted text-sm">
          This event has expenses or settlements. Settle up and delete expenses
          before deleting the event.
        </p>
        <div class="mt-6 flex justify-end">
          <AppButton variant="secondary" @click="showDeleteConfirm = false">
            Got it
          </AppButton>
        </div>
      </template>

      <template v-else>
        <p class="text-ink-muted text-sm">
          Permanently delete
          <strong class="text-ink">{{ event?.name }}</strong
          >? This can't be undone.
        </p>
        <p v-if="deleteSummary.length > 0" class="text-ink-muted mt-2 text-sm">
          This will also delete {{ deleteSummary.join(', ') }}.
        </p>
        <div class="mt-6 flex justify-end gap-3">
          <TextButton variant="secondary" @click="showDeleteConfirm = false">
            Cancel
          </TextButton>
          <AppButton
            variant="danger"
            :loading="deleting"
            @click="handleDeleteEvent"
          >
            Delete event
          </AppButton>
        </div>
      </template>
    </BaseModal>
  </template>
</template>
