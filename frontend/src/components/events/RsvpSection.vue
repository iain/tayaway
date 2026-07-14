<script setup lang="ts">
import { computed, ref } from 'vue'
import { CheckCircleIcon, XCircleIcon } from '@heroicons/vue/24/solid'
import {
  UserIcon,
  UserPlusIcon,
  CalendarDaysIcon,
  ChevronLeftIcon,
  ChevronRightIcon,
  XMarkIcon,
} from '@heroicons/vue/24/outline'
import { useAttendancesStore } from '@/stores/attendances'
import { useGuestsStore } from '@/stores/guests'
import RsvpActionsMenu from '@/components/events/RsvpActionsMenu.vue'
import { useObjectPoolStore } from '@/stores/objectPool'
import type {
  HydratedAttendance,
  HydratedEvent,
} from '@/composables/useHydratedEvent'
import { useCalendar } from '@/composables/useCalendar'
import BaseCard from '@/components/common/BaseCard.vue'
import BaseModal from '@/components/common/BaseModal.vue'
import AppButton from '@/components/common/AppButton.vue'
import AppInput from '@/components/common/AppInput.vue'
import TextButton from '@/components/common/TextButton.vue'
import IconButton from '@/components/common/IconButton.vue'
import CalendarMonth from '@/components/calendar/CalendarMonth.vue'
import { attendanceDates, enumerateDates } from '@/utils/event'

const props = defineProps<{
  event: HydratedEvent
  currentUserId: string | null
}>()

const attendancesStore = useAttendancesStore()
const guestsStore = useGuestsStore()
const pool = useObjectPoolStore()
const { formatDateDisplay } = useCalendar()

function filedByLabel(attendance: HydratedAttendance) {
  const filer = attendance.createdByUserId
  if (filer == null || filer === attendance.userId) return null
  const m = pool.findBy('member', 'userId', filer)
  return m?.name || m?.email || 'Unknown'
}

function memberName(userId: string): string {
  const m = pool.findBy('member', 'userId', userId)
  return m?.name || m?.email || 'Unknown'
}

// --- Attendance rows, resolved via the hydrated attendee ---

const memberRows = computed(() =>
  props.event.attendances.filter((a) => !a.attendee.isGuest)
)
const guestRows = computed(() =>
  props.event.attendances.filter((a) => a.attendee.isGuest)
)

const going = computed(() =>
  memberRows.value.filter((a) => a.status === 'going')
)
const goingGuests = computed(() =>
  guestRows.value.filter((a) => a.status === 'going')
)
const declined = computed(() =>
  memberRows.value.filter((a) => a.status === 'declined')
)

// "No response" has two forms (doc/attendances.md): no row at all, or a row
// reverted to pending by a date reset. Both land here.
const noResponse = computed(() => {
  if (!props.event.workspace) return []
  const answered = new Set(
    memberRows.value.filter((a) => a.status !== 'pending').map((a) => a.userId)
  )
  return props.event.workspace.members.filter((m) => !answered.has(m.userId))
})

const currentUserAttendance = computed(() => {
  if (!props.currentUserId) return undefined
  return memberRows.value.find((a) => a.userId === props.currentUserId)
})

const eventDays = computed(() =>
  props.event.startDate && props.event.endDate
    ? enumerateDates(props.event.startDate, props.event.endDate)
    : []
)

function daysFor(attendance: HydratedAttendance): string[] {
  if (!props.event.startDate || !props.event.endDate) return []
  return attendanceDates(attendance, props.event.startDate, props.event.endDate)
}

function isPartialDays(attendance: HydratedAttendance): boolean {
  return (
    attendance.days != null &&
    daysFor(attendance).length < eventDays.value.length
  )
}

function attendanceSummary(attendance: HydratedAttendance): string {
  return daysFor(attendance)
    .map((d) => formatDateDisplay(d))
    .join(', ')
}

// --- Attend / decline ---

// Whose decline got blocked, and by what. The discriminated union prevents a
// member named "self" from colliding with the self-decline sentinel.
type DeclineBlocked =
  | { type: 'self'; reason: 'expenses' | 'guests' }
  | { type: 'other'; name: string; reason: 'expenses' | 'guests' }
const declineBlocked = ref<DeclineBlocked | null>(null)

function userHasExpensesFor(userId: string): boolean {
  return pool
    .getAll('expense')
    .some((e) => e.eventId === props.event.id && e.userId === userId)
}

function userHostsGoingGuests(userId: string): boolean {
  return goingGuests.value.some((a) => a.hostUserId === userId)
}

async function handleAttend(): Promise<void> {
  try {
    await attendancesStore.submitMemberAttendance(props.event.id, 'going')
  } catch {
    // Error handled by store
  }
}

async function handleDecline(): Promise<void> {
  if (props.currentUserId == null) return
  await setStatusFor(props.currentUserId, 'declined')
}

async function setStatusFor(
  userId: string,
  status: 'going' | 'declined'
): Promise<void> {
  if (status === 'declined') {
    const reason = userHasExpensesFor(userId)
      ? ('expenses' as const)
      : userHostsGoingGuests(userId)
        ? ('guests' as const)
        : null
    if (reason) {
      declineBlocked.value =
        userId === props.currentUserId
          ? { type: 'self', reason }
          : { type: 'other', name: memberName(userId), reason }
      return
    }
  }
  try {
    await attendancesStore.submitMemberAttendance(props.event.id, status, {
      onBehalfOfUserId: userId === props.currentUserId ? undefined : userId,
    })
  } catch {
    // Error handled by store
  }
}

type RsvpActionKind =
  | 'attend'
  | 'decline'
  | 'set-dates'
  | 'change-dates'
  | 'rename'

interface RsvpAction {
  kind: RsvpActionKind
  label: string
  danger?: boolean
}

function actionsFor(attendance: HydratedAttendance | null): RsvpAction[] {
  if (attendance == null || attendance.status === 'pending') {
    return [
      { kind: 'attend', label: 'Mark as attending' },
      { kind: 'decline', label: 'Mark as not attending', danger: true },
    ]
  }
  if (attendance.status === 'going') {
    return [
      attendance.days != null
        ? { kind: 'change-dates', label: 'Change days' }
        : { kind: 'set-dates', label: 'Choose days' },
      { kind: 'decline', label: 'Mark as not attending', danger: true },
    ]
  }
  return [{ kind: 'attend', label: 'Mark as attending' }]
}

function handlePick(userId: string, kind: RsvpActionKind): void {
  if (kind === 'attend') setStatusFor(userId, 'going')
  else if (kind === 'decline') setStatusFor(userId, 'declined')
  else openDayPicker(userId)
}

// --- Member day picker (self and on-behalf flows) ---

const showDayPicker = ref(false)
const selectedDaySet = ref<Set<string>>(new Set())
const selectedDays = computed(() => [...selectedDaySet.value].sort())
// Subject of the day picker. `null` means current user; set to another user
// id when a member edits someone else's attendance.
const dayPickerUserId = ref<string | null>(null)

// Calendar navigation — start on the month of the event start date
const calYear = ref(new Date().getFullYear())
const calMonth = ref(new Date().getMonth())

function navigateToEventStart(): void {
  if (props.event.startDate) {
    const [y, m] = props.event.startDate.split('-').map(Number) as [
      number,
      number,
    ]
    calYear.value = y
    calMonth.value = m - 1
  }
}

function findAttendanceFor(userId: string) {
  return memberRows.value.find((a) => a.userId === userId)
}

function openDayPicker(forUserId?: string): void {
  const targetUserId = forUserId ?? props.currentUserId ?? null
  dayPickerUserId.value =
    targetUserId === props.currentUserId ? null : targetUserId
  const attendance =
    targetUserId == null ? undefined : findAttendanceFor(targetUserId)
  // Preset to their current days; a whole-event or new attendance starts
  // with every day selected.
  const preset =
    attendance && attendance.status === 'going'
      ? daysFor(attendance)
      : eventDays.value
  selectedDaySet.value = new Set(preset)
  navigateToEventStart()
  showDayPicker.value = true
}

function toggleDay(dateString: string): void {
  const next = new Set(selectedDaySet.value)
  if (next.has(dateString)) next.delete(dateString)
  else next.add(dateString)
  selectedDaySet.value = next
}

// Shift-click range: add every day between the two clicks (inclusive).
function selectDayRange(from: string, to: string): void {
  const [start, end] = from <= to ? [from, to] : [to, from]
  const next = new Set(selectedDaySet.value)
  for (const d of enumerateDates(start, end)) next.add(d)
  selectedDaySet.value = next
}

function selectWholeEvent(): void {
  selectedDaySet.value = new Set(eventDays.value)
}

function navigatePrev(): void {
  if (calMonth.value === 0) {
    calMonth.value = 11
    calYear.value--
  } else {
    calMonth.value--
  }
}

function navigateNext(): void {
  if (calMonth.value === 11) {
    calMonth.value = 0
    calYear.value++
  } else {
    calMonth.value++
  }
}

const daySelectionText = computed(() => {
  const n = selectedDaySet.value.size
  const total = eventDays.value.length
  if (n === 0) return 'Pick at least one day'
  if (n === total) return `Whole event (${total} days)`
  return `${n} of ${total} days`
})

const canSaveDays = computed(() => selectedDaySet.value.size > 0)

const dayPickerTitle = computed(() =>
  dayPickerUserId.value == null
    ? 'Your attendance days'
    : `Attendance days for ${memberName(dayPickerUserId.value)}`
)

async function handleSaveDays(): Promise<void> {
  const days = selectedDays.value
  if (days.length === 0) return
  // Selecting every day is just "the whole event" — send null so it's
  // stored canonically, matching the server's normalization.
  const isWholeEvent = days.length === eventDays.value.length
  try {
    await attendancesStore.submitMemberAttendance(props.event.id, 'going', {
      days: isWholeEvent ? null : days,
      onBehalfOfUserId: dayPickerUserId.value ?? undefined,
    })
    showDayPicker.value = false
  } catch {
    // Error handled by store
  }
}

// --- Guests: add / change days / rename / remove ---

interface GuestModalState {
  /** Set when changing days of an existing attendance row. */
  attendanceId: string | null
  /** Existing workspace guest, either picked or behind attendanceId. */
  guestId: string | null
  name: string
  days: Set<string>
}
const guestModal = ref<GuestModalState | null>(null)

// Existing guests to offer before creating a new one: the workspace's
// guests minus anyone already going on this event. Placeholders stay hidden
// until renamed (doc/attendances.md).
const pickableGuests = computed(() => {
  const goingGuestIds = new Set(goingGuests.value.map((a) => a.guestId))
  return pool
    .getAll('guest')
    .filter(
      (g) =>
        g.workspaceId === props.event.workspaceId &&
        !g.placeholder &&
        !goingGuestIds.has(g.id)
    )
    .sort((a, b) => a.name.localeCompare(b.name))
})

function openAddGuest(): void {
  guestModal.value = {
    attendanceId: null,
    guestId: null,
    name: '',
    days: new Set(eventDays.value),
  }
  navigateToEventStart()
}

function openGuestDays(attendance: HydratedAttendance): void {
  guestModal.value = {
    attendanceId: attendance.id,
    guestId: attendance.guestId,
    name: attendance.attendee.name,
    days: new Set(daysFor(attendance)),
  }
  navigateToEventStart()
}

function pickExistingGuest(guestId: string, name: string): void {
  if (!guestModal.value) return
  guestModal.value = { ...guestModal.value, guestId, name }
}

function toggleGuestDay(dateString: string): void {
  if (!guestModal.value) return
  const next = new Set(guestModal.value.days)
  if (next.has(dateString)) next.delete(dateString)
  else next.add(dateString)
  guestModal.value = { ...guestModal.value, days: next }
}

function selectGuestDayRange(from: string, to: string): void {
  if (!guestModal.value) return
  const [start, end] = from <= to ? [from, to] : [to, from]
  const next = new Set(guestModal.value.days)
  for (const d of enumerateDates(start, end)) next.add(d)
  guestModal.value = { ...guestModal.value, days: next }
}

const guestModalTitle = computed(() =>
  guestModal.value?.attendanceId
    ? `Days for ${guestModal.value.name}`
    : 'Add a guest'
)

const canSaveGuest = computed(() => {
  const modal = guestModal.value
  if (!modal) return false
  if (modal.days.size === 0) return false
  return modal.guestId != null || modal.name.trim().length > 0
})

async function handleSaveGuest(): Promise<void> {
  const modal = guestModal.value
  if (!modal || !canSaveGuest.value) return
  const sorted = [...modal.days].sort()
  const days = sorted.length === eventDays.value.length ? null : sorted
  try {
    await attendancesStore.upsertGuestAttendance(
      props.event.id,
      props.event.workspaceId,
      modal.guestId
        ? { guestId: modal.guestId, days }
        : { name: modal.name.trim(), days }
    )
    guestModal.value = null
  } catch {
    // Error handled by store
  }
}

async function handleRemoveGuest(
  attendance: HydratedAttendance
): Promise<void> {
  try {
    await attendancesStore.removeGuest(props.event.id, attendance.id)
  } catch {
    // Error handled by store
  }
}

const renameModal = ref<{ guestId: string; name: string } | null>(null)

function openRenameGuest(attendance: HydratedAttendance): void {
  if (!attendance.guestId) return
  renameModal.value = {
    guestId: attendance.guestId,
    name: attendance.attendee.name,
  }
}

async function handleRenameGuest(): Promise<void> {
  const modal = renameModal.value
  if (!modal || modal.name.trim().length === 0) return
  try {
    await guestsStore.renameGuest(
      props.event.workspaceId,
      modal.guestId,
      modal.name.trim()
    )
    renameModal.value = null
  } catch {
    // Error handled by store
  }
}

function handleGuestPick(
  attendance: HydratedAttendance,
  kind: RsvpActionKind
): void {
  if (kind === 'change-dates' || kind === 'set-dates') openGuestDays(attendance)
  else if (kind === 'rename') openRenameGuest(attendance)
  else if (kind === 'decline') handleRemoveGuest(attendance)
}

function guestActions(attendance: HydratedAttendance): RsvpAction[] {
  return [
    attendance.days != null
      ? { kind: 'change-dates', label: 'Change days' }
      : { kind: 'set-dates', label: 'Choose days' },
    { kind: 'rename', label: 'Rename guest' },
  ]
}

function guestOfLabel(attendance: HydratedAttendance): string {
  const host = attendance.attendee.hostMember
  return `guest of ${host?.name || host?.email || 'Unknown'}`
}
</script>

<template>
  <section data-testid="rsvp-section">
    <BaseCard padded>
      <!-- Current user response toggle -->
      <div class="mb-6">
        <p class="text-ink mb-2 text-sm font-medium">Your response</p>

        <div class="flex gap-2">
          <button
            type="button"
            data-testid="rsvp-attend"
            :aria-pressed="
              currentUserAttendance?.status === 'going' ? 'true' : 'false'
            "
            class="focus-visible:outline-focus inline-flex cursor-pointer items-center gap-2 rounded-md px-4 py-2 text-sm font-semibold shadow-sm transition-colors focus-visible:outline-2 focus-visible:outline-offset-2"
            :class="
              currentUserAttendance?.status === 'going'
                ? 'bg-green-600 text-white'
                : 'bg-btn-secondary-fill text-btn-secondary-ink hover:bg-btn-secondary-fill-hover'
            "
            @click="handleAttend"
          >
            <CheckCircleIcon class="size-4" aria-hidden="true" />
            Attending
          </button>
          <button
            type="button"
            data-testid="rsvp-decline"
            :aria-pressed="
              currentUserAttendance?.status === 'declined' ? 'true' : 'false'
            "
            class="focus-visible:outline-focus inline-flex cursor-pointer items-center gap-2 rounded-md px-4 py-2 text-sm font-semibold shadow-sm transition-colors focus-visible:outline-2 focus-visible:outline-offset-2"
            :class="
              currentUserAttendance?.status === 'declined'
                ? 'bg-red-600 text-white'
                : 'bg-btn-secondary-fill text-btn-secondary-ink hover:bg-btn-secondary-fill-hover'
            "
            @click="handleDecline"
          >
            <XCircleIcon class="size-4" aria-hidden="true" />
            Not Attending
          </button>
        </div>

        <!-- Partial attendance + guest entry points -->
        <div v-if="currentUserAttendance?.status === 'going'" class="mt-4">
          <div
            v-if="isPartialDays(currentUserAttendance)"
            class="text-ink-muted mb-2 flex items-start gap-1.5 text-sm"
            data-testid="rsvp-attendance-days"
          >
            <CalendarDaysIcon class="mt-0.5 size-4 shrink-0" />
            <span>
              {{ attendanceSummary(currentUserAttendance) }}
              <span class="text-ink-muted">(partial)</span>
            </span>
          </div>
          <div class="flex items-center gap-4">
            <TextButton
              v-if="!showDayPicker"
              data-testid="rsvp-change-dates"
              @click="openDayPicker()"
            >
              {{
                currentUserAttendance.days != null
                  ? 'Change days'
                  : 'Choose days'
              }}
            </TextButton>
            <TextButton data-testid="rsvp-add-guest" @click="openAddGuest">
              <span class="inline-flex items-center gap-1">
                <UserPlusIcon class="size-4" aria-hidden="true" />
                Add a guest
              </span>
            </TextButton>
          </div>
        </div>
      </div>

      <!-- Day picker modal — shared by self and on-behalf flows -->
      <BaseModal
        :open="showDayPicker"
        :title="dayPickerTitle"
        size="sm"
        @close="showDayPicker = false"
      >
        <div class="text-ink-muted mb-4 text-sm">
          Tap the days you'll be here, or shift-click for a range.
          {{ daySelectionText }}.
        </div>

        <div class="mb-4 flex items-center justify-between">
          <IconButton label="Previous month" @click="navigatePrev">
            <ChevronLeftIcon class="size-5" />
          </IconButton>
          <IconButton label="Next month" @click="navigateNext">
            <ChevronRightIcon class="size-5" />
          </IconButton>
        </div>

        <CalendarMonth
          :year="calYear"
          :month="calMonth"
          :selected-start="null"
          :selected-end="null"
          :hover-date="null"
          :selected-dates="selectedDays"
          :min-date="event.startDate ?? undefined"
          :max-date="event.endDate ?? undefined"
          @select="toggleDay"
          @select-range="selectDayRange"
        />

        <div class="mt-6 flex items-center justify-between">
          <div>
            <TextButton variant="secondary" @click="selectWholeEvent">
              Whole event
            </TextButton>
          </div>
          <div class="flex items-center gap-3">
            <TextButton variant="secondary" @click="showDayPicker = false">
              Cancel
            </TextButton>
            <AppButton :disabled="!canSaveDays" @click="handleSaveDays">
              Save
            </AppButton>
          </div>
        </div>
      </BaseModal>

      <!-- Guest modal — add a new/existing guest, or change a guest's days -->
      <BaseModal
        :open="guestModal !== null"
        :title="guestModalTitle"
        size="sm"
        @close="guestModal = null"
      >
        <template v-if="guestModal">
          <template v-if="guestModal.attendanceId === null">
            <div v-if="pickableGuests.length > 0" class="mb-4">
              <p class="text-ink-muted mb-2 text-sm">
                Someone who's been along before?
              </p>
              <ul
                class="flex flex-wrap gap-2"
                data-testid="guest-picker-existing"
              >
                <li v-for="guest in pickableGuests" :key="guest.id">
                  <button
                    type="button"
                    class="focus-visible:outline-focus cursor-pointer rounded-full px-3 py-1 text-sm transition-colors focus-visible:outline-2 focus-visible:outline-offset-2"
                    :class="
                      guestModal.guestId === guest.id
                        ? 'bg-green-600 text-white'
                        : 'bg-btn-secondary-fill text-btn-secondary-ink hover:bg-btn-secondary-fill-hover'
                    "
                    @click="pickExistingGuest(guest.id, guest.name)"
                  >
                    {{ guest.name }}
                  </button>
                </li>
              </ul>
            </div>

            <div v-if="guestModal.guestId === null" class="mb-4">
              <label
                class="text-ink mb-1 block text-sm font-medium"
                for="guest-name"
              >
                {{ pickableGuests.length > 0 ? 'Or add someone new' : 'Name' }}
              </label>
              <AppInput
                id="guest-name"
                data-testid="guest-name-input"
                :model-value="guestModal.name"
                placeholder="Guest's name"
                @update:model-value="
                  guestModal = { ...guestModal, name: $event as string }
                "
              />
            </div>
          </template>

          <div class="text-ink-muted mb-4 text-sm">
            Which days
            {{ guestModal.name ? `is ${guestModal.name}` : 'are they' }}
            coming along?
          </div>

          <div class="mb-4 flex items-center justify-between">
            <IconButton label="Previous month" @click="navigatePrev">
              <ChevronLeftIcon class="size-5" />
            </IconButton>
            <IconButton label="Next month" @click="navigateNext">
              <ChevronRightIcon class="size-5" />
            </IconButton>
          </div>

          <CalendarMonth
            :year="calYear"
            :month="calMonth"
            :selected-start="null"
            :selected-end="null"
            :hover-date="null"
            :selected-dates="[...guestModal.days].sort()"
            :min-date="event.startDate ?? undefined"
            :max-date="event.endDate ?? undefined"
            @select="toggleGuestDay"
            @select-range="selectGuestDayRange"
          />

          <div class="mt-6 flex items-center justify-end gap-3">
            <TextButton variant="secondary" @click="guestModal = null">
              Cancel
            </TextButton>
            <AppButton
              data-testid="guest-save"
              :disabled="!canSaveGuest"
              @click="handleSaveGuest"
            >
              Save
            </AppButton>
          </div>
        </template>
      </BaseModal>

      <!-- Rename guest modal -->
      <BaseModal
        :open="renameModal !== null"
        title="Rename guest"
        size="sm"
        @close="renameModal = null"
      >
        <template v-if="renameModal">
          <AppInput
            data-testid="guest-rename-input"
            :model-value="renameModal.name"
            @update:model-value="
              renameModal = { ...renameModal, name: $event as string }
            "
          />
          <div class="mt-6 flex items-center justify-end gap-3">
            <TextButton variant="secondary" @click="renameModal = null">
              Cancel
            </TextButton>
            <AppButton
              data-testid="guest-rename-save"
              :disabled="renameModal.name.trim().length === 0"
              @click="handleRenameGuest"
            >
              Save
            </AppButton>
          </div>
        </template>
      </BaseModal>

      <!-- Attendee lists -->
      <div class="space-y-4">
        <!-- Attending -->
        <div v-if="going.length > 0 || goingGuests.length > 0">
          <h3 class="text-state-success-ink mb-2 text-sm font-medium">
            Attending ({{ going.length + goingGuests.length }})
          </h3>
          <ul class="space-y-2">
            <li
              v-for="attendance in going"
              :key="attendance.id"
              class="bg-state-success-fill flex items-center gap-3 rounded-md px-3 py-2"
            >
              <div
                class="flex size-8 items-center justify-center rounded-full bg-green-200 dark:bg-green-800"
              >
                <CheckCircleIcon class="text-state-success-ink size-4" />
              </div>
              <div class="min-w-0 flex-1">
                <span class="text-ink">
                  {{ attendance.attendee.name }}
                  <span
                    v-if="attendance.userId === currentUserId"
                    class="text-state-success-ink text-sm"
                  >
                    (you)
                  </span>
                  <span
                    v-if="filedByLabel(attendance)"
                    class="text-ink-muted text-sm"
                    data-testid="rsvp-filed-by"
                  >
                    (RSVP'd by {{ filedByLabel(attendance) }})
                  </span>
                </span>
                <p
                  v-if="isPartialDays(attendance)"
                  class="text-ink-muted text-xs"
                >
                  {{ attendanceSummary(attendance) }}
                </p>
              </div>
              <RsvpActionsMenu
                v-if="attendance.userId !== currentUserId"
                :menu-label="`Manage RSVP for ${attendance.attendee.name}`"
                :actions="actionsFor(attendance)"
                @pick="handlePick(attendance.userId!, $event)"
              />
            </li>

            <!-- Going guests ride the attending list, attributed to their host -->
            <li
              v-for="attendance in goingGuests"
              :key="attendance.id"
              data-testid="attendance-guest-row"
              class="bg-state-success-fill flex items-center gap-3 rounded-md px-3 py-2"
            >
              <div
                class="flex size-8 items-center justify-center rounded-full bg-green-200 dark:bg-green-800"
              >
                <UserPlusIcon class="text-state-success-ink size-4" />
              </div>
              <div class="min-w-0 flex-1">
                <span class="text-ink">
                  {{ attendance.attendee.name }}
                  <span class="text-ink-muted text-sm">
                    ({{ guestOfLabel(attendance) }})
                  </span>
                </span>
                <p
                  v-if="isPartialDays(attendance)"
                  class="text-ink-muted text-xs"
                >
                  {{ attendanceSummary(attendance) }}
                </p>
              </div>
              <RsvpActionsMenu
                :menu-label="`Manage guest ${attendance.attendee.name}`"
                :actions="guestActions(attendance)"
                @pick="handleGuestPick(attendance, $event)"
              />
              <IconButton
                data-testid="guest-remove"
                :label="`Remove ${attendance.attendee.name} from this event`"
                @click="handleRemoveGuest(attendance)"
              >
                <XMarkIcon class="size-5" />
              </IconButton>
            </li>
          </ul>
        </div>

        <!-- Not attending -->
        <div v-if="declined.length > 0">
          <h3 class="text-state-danger-ink mb-2 text-sm font-medium">
            Not Attending ({{ declined.length }})
          </h3>
          <ul class="space-y-2">
            <li
              v-for="attendance in declined"
              :key="attendance.id"
              class="bg-state-danger-fill flex items-center gap-3 rounded-md px-3 py-2"
            >
              <div
                class="flex size-8 items-center justify-center rounded-full bg-red-200 dark:bg-red-800"
              >
                <XCircleIcon class="text-state-danger-ink size-4" />
              </div>
              <span class="text-ink min-w-0 flex-1">
                {{ attendance.attendee.name }}
                <span
                  v-if="attendance.userId === currentUserId"
                  class="text-state-danger-ink text-sm"
                >
                  (you)
                </span>
                <span
                  v-if="filedByLabel(attendance)"
                  class="text-ink-muted text-sm"
                  data-testid="rsvp-filed-by"
                >
                  (RSVP'd by {{ filedByLabel(attendance) }})
                </span>
              </span>
              <RsvpActionsMenu
                v-if="attendance.userId !== currentUserId"
                :menu-label="`Manage RSVP for ${attendance.attendee.name}`"
                :actions="actionsFor(attendance)"
                @pick="handlePick(attendance.userId!, $event)"
              />
            </li>
          </ul>
        </div>

        <!-- No response -->
        <div v-if="noResponse.length > 0">
          <h3 class="text-ink-muted mb-2 text-sm font-medium">
            No Response ({{ noResponse.length }})
          </h3>
          <ul class="space-y-2">
            <li
              v-for="member in noResponse"
              :key="member.id"
              class="bg-surface-sunken flex items-center gap-3 rounded-md px-3 py-2"
            >
              <div
                class="bg-line flex size-8 items-center justify-center rounded-full"
              >
                <UserIcon class="text-ink-muted size-4" />
              </div>
              <span class="text-ink min-w-0 flex-1">
                {{ member.name || member.email || 'Unknown' }}
                <span
                  v-if="member.userId === currentUserId"
                  class="text-sm text-amber-600 dark:text-amber-400"
                >
                  (you)
                </span>
              </span>
              <RsvpActionsMenu
                v-if="member.userId !== currentUserId"
                :menu-label="`Manage RSVP for ${member.name ?? 'member'}`"
                :actions="actionsFor(findAttendanceFor(member.userId) ?? null)"
                @pick="handlePick(member.userId, $event)"
              />
            </li>
          </ul>
        </div>

        <!-- Summary -->
        <p v-if="event.attendances.length > 0" class="text-ink-muted text-sm">
          {{ going.length }} attending<span v-if="goingGuests.length > 0">
            (+{{ goingGuests.length }}
            {{ goingGuests.length === 1 ? 'guest' : 'guests' }})</span
          >, {{ declined.length }} not attending, {{ noResponse.length }}
          pending
        </p>
      </div>

      <BaseModal
        :open="declineBlocked !== null"
        title="Cannot decline"
        size="sm"
        @close="declineBlocked = null"
      >
        <p class="text-ink-muted text-sm">
          <template
            v-if="
              declineBlocked?.type === 'self' &&
              declineBlocked.reason === 'expenses'
            "
          >
            You have expenses on this event. Delete your expenses before
            changing your RSVP to not attending.
          </template>
          <template
            v-else-if="
              declineBlocked?.type === 'self' &&
              declineBlocked.reason === 'guests'
            "
          >
            You have guests going on this event. Remove your guests first, then
            decline.
          </template>
          <template
            v-else-if="
              declineBlocked?.type === 'other' &&
              declineBlocked.reason === 'expenses'
            "
          >
            {{ declineBlocked.name }} has expenses on this event. Delete those
            expenses before marking them as not attending.
          </template>
          <template v-else-if="declineBlocked?.type === 'other'">
            {{ declineBlocked.name }} has guests going on this event. Remove
            their guests first, then mark them as not attending.
          </template>
        </p>
        <div class="mt-6 flex justify-end gap-3">
          <TextButton variant="secondary" @click="declineBlocked = null">
            Cancel
          </TextButton>
          <AppButton
            v-if="declineBlocked?.reason === 'expenses'"
            :to="`/events/${event.id}/expenses`"
            autofocus
            @click="declineBlocked = null"
          >
            Go to Expenses
          </AppButton>
        </div>
      </BaseModal>
    </BaseCard>
  </section>
</template>
