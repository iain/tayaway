<script setup lang="ts">
import { computed, ref } from 'vue'
import { CheckCircleIcon, XCircleIcon } from '@heroicons/vue/24/solid'
import {
  UserIcon,
  UserPlusIcon,
  CalendarDaysIcon,
  ChevronLeftIcon,
  ChevronRightIcon,
} from '@heroicons/vue/24/outline'
import { useRsvpsStore } from '@/stores/rsvps'
import RsvpActionsMenu from '@/components/events/RsvpActionsMenu.vue'
import { useObjectPoolStore } from '@/stores/objectPool'
import type { HydratedEvent } from '@/composables/useHydratedEvent'
import { useCalendar } from '@/composables/useCalendar'
import BaseCard from '@/components/common/BaseCard.vue'
import BaseModal from '@/components/common/BaseModal.vue'
import DateRangeDisplay from '@/components/common/DateRangeDisplay.vue'
import AppButton from '@/components/common/AppButton.vue'
import TextButton from '@/components/common/TextButton.vue'
import IconButton from '@/components/common/IconButton.vue'
import CalendarMonth from '@/components/calendar/CalendarMonth.vue'
import {
  attendedDates,
  attendedDays,
  enumerateDates,
  type AttendanceEntry,
} from '@/utils/event'

// Mirrors backend ValidationLimits::PLUS_ONES_PER_DAY_MAX.
const PLUS_ONES_MAX = 20

const props = defineProps<{
  event: HydratedEvent
  currentUserId: string | null
}>()

const rsvpsStore = useRsvpsStore()
const pool = useObjectPoolStore()
const { formatDateDisplay } = useCalendar()

function filedByLabel(rsvp: {
  userId: string
  createdByUserId: string | null
}) {
  const filer = rsvp.createdByUserId
  if (filer == null || filer === rsvp.userId) return null
  const m = pool.findBy('member', 'userId', filer)
  return m?.name || m?.email || 'Unknown'
}

function memberName(userId: string): string {
  const m = pool.findBy('member', 'userId', userId)
  return m?.name || m?.email || 'Unknown'
}

const showDayPicker = ref(false)
// Source of truth while the picker is open: selected day → guest count for that
// day. The calendar's selected-day set is just the keys.
const dayGuests = ref<Map<string, number>>(new Map())
const selectedDays = computed(() => [...dayGuests.value.keys()].sort())
// Subject of the day picker. `null` means current user (the existing self-RSVP
// flow); set to another user id when an admin edits someone else's attendance.
const dayPickerUserId = ref<string | null>(null)
// Whose decline got blocked by existing expenses. `null` when nobody is
// blocked (modal closed). The discriminated union prevents a member named
// "self" from colliding with the self-decline sentinel.
type DeclineBlocked = { type: 'self' } | { type: 'other'; name: string }
const declineBlocked = ref<DeclineBlocked | null>(null)

// Calendar navigation — start on the month of the event start date
const calYear = ref(new Date().getFullYear())
const calMonth = ref(new Date().getMonth())

const currentUserRsvp = computed(() => {
  if (!props.currentUserId) return undefined
  return props.event.rsvps.find((r) => r.userId === props.currentUserId)
})

const attending = computed(() => props.event.rsvps.filter((r) => r.attending))

const notAttending = computed(() =>
  props.event.rsvps.filter((r) => !r.attending)
)

const noResponse = computed(() => {
  if (!props.event.workspace) return []
  const rsvpUserIds = new Set(props.event.rsvps.map((r) => r.userId))
  return props.event.workspace.members.filter((m) => !rsvpUserIds.has(m.userId))
})

const eventDays = computed(() =>
  props.event.startDate && props.event.endDate
    ? enumerateDates(props.event.startDate, props.event.endDate)
    : []
)

type AttendanceLike = {
  attendance: AttendanceEntry[] | null
  startDate: string | null
  endDate: string | null
}

// The concrete set of ISO days an RSVP covers, resolved against the event.
function daysForRsvp(rsvp: AttendanceLike): string[] {
  if (!props.event.startDate || !props.event.endDate) return []
  return attendedDates(rsvp, props.event.startDate, props.event.endDate)
}

// Total guests ("+1"s) across all the RSVP's attended days.
function guestCountFor(rsvp: AttendanceLike): number {
  if (!props.event.startDate || !props.event.endDate) return 0
  return attendedDays(rsvp, props.event.startDate, props.event.endDate).reduce(
    (sum, d) => sum + d.plusOnes,
    0
  )
}

// True when the RSVP covers a subset of the event (come-and-go or legacy range)
// rather than the whole event.
function isPartialRsvp(rsvp: {
  attendance: AttendanceEntry[] | null
  startDate: string | null
}): boolean {
  return rsvp.attendance != null || rsvp.startDate != null
}

// True when the day set is a real subset of the event — used for the "(partial)"
// label, which a whole-event-with-guests RSVP should not get.
function isPartialDays(rsvp: AttendanceLike): boolean {
  return daysForRsvp(rsvp).length < eventDays.value.length
}

function attendanceSummary(rsvp: AttendanceLike): string {
  return daysForRsvp(rsvp)
    .map((d) => formatDateDisplay(d))
    .join(', ')
}

function guestSummary(rsvp: AttendanceLike): string {
  const guests = guestCountFor(rsvp)
  return `+${guests} guest${guests === 1 ? '' : 's'}`
}

// Guests brought by everyone currently marked attending — folded into the
// headcount summary.
const totalAttendingGuests = computed(() =>
  attending.value.reduce((sum, rsvp) => sum + guestCountFor(rsvp), 0)
)

async function handleAttend(): Promise<void> {
  try {
    await rsvpsStore.submitRsvp(props.event.id, true)
  } catch {
    // Error handled by store
  }
}

function userHasExpensesFor(userId: string): boolean {
  return pool
    .getAll('expense')
    .some((e) => e.eventId === props.event.id && e.userId === userId)
}

async function handleDecline(): Promise<void> {
  if (props.currentUserId == null) return
  await setRsvpFor(props.currentUserId, false)
}

async function setRsvpFor(userId: string, attending: boolean): Promise<void> {
  if (!attending && userHasExpensesFor(userId)) {
    declineBlocked.value =
      userId === props.currentUserId
        ? { type: 'self' }
        : { type: 'other', name: memberName(userId) }
    return
  }
  try {
    await rsvpsStore.submitRsvp(props.event.id, attending, {
      onBehalfOfUserId: userId === props.currentUserId ? undefined : userId,
    })
  } catch {
    // Error handled by store
  }
}

function findRsvpFor(userId: string) {
  return props.event.rsvps.find((r) => r.userId === userId)
}

type RsvpActionKind = 'attend' | 'decline' | 'set-dates' | 'change-dates'

interface RsvpAction {
  kind: RsvpActionKind
  label: string
  danger?: boolean
}

function actionsFor(
  rsvp: {
    attending: boolean
    attendance: AttendanceEntry[] | null
    startDate: string | null
  } | null
): RsvpAction[] {
  if (rsvp == null) {
    return [
      { kind: 'attend', label: 'Mark as attending' },
      { kind: 'decline', label: 'Mark as not attending', danger: true },
    ]
  }
  if (rsvp.attending) {
    return [
      isPartialRsvp(rsvp)
        ? { kind: 'change-dates', label: 'Change days' }
        : { kind: 'set-dates', label: 'Choose days' },
      { kind: 'decline', label: 'Mark as not attending', danger: true },
    ]
  }
  return [{ kind: 'attend', label: 'Mark as attending' }]
}

function handlePick(userId: string, kind: RsvpActionKind): void {
  if (kind === 'attend') setRsvpFor(userId, true)
  else if (kind === 'decline') setRsvpFor(userId, false)
  else openDayPicker(userId)
}

function openDayPicker(forUserId?: string): void {
  const targetUserId = forUserId ?? props.currentUserId ?? null
  dayPickerUserId.value =
    targetUserId === props.currentUserId ? null : targetUserId
  const rsvp = targetUserId == null ? undefined : findRsvpFor(targetUserId)
  // Preset to their current days and guest counts; a whole-event or new RSVP
  // starts with every day selected and no guests.
  const preset =
    rsvp && props.event.startDate && props.event.endDate
      ? attendedDays(rsvp, props.event.startDate, props.event.endDate)
      : eventDays.value.map((date) => ({ date, plusOnes: 0 }))
  dayGuests.value = new Map(preset.map((d) => [d.date, d.plusOnes]))

  // Navigate to the month of the event start
  if (props.event.startDate) {
    const [y, m] = props.event.startDate.split('-').map(Number) as [
      number,
      number,
    ]
    calYear.value = y
    calMonth.value = m - 1
  }
  showDayPicker.value = true
}

function toggleDay(dateString: string): void {
  const next = new Map(dayGuests.value)
  if (next.has(dateString)) next.delete(dateString)
  else next.set(dateString, 0)
  dayGuests.value = next
}

// Shift-click range: add every day between the two clicks (inclusive), keeping
// any guest counts already set. Days are still stored individually.
function selectDayRange(from: string, to: string): void {
  const [start, end] = from <= to ? [from, to] : [to, from]
  const next = new Map(dayGuests.value)
  for (const d of enumerateDates(start, end)) if (!next.has(d)) next.set(d, 0)
  dayGuests.value = next
}

function selectWholeEvent(): void {
  const next = new Map(dayGuests.value)
  for (const d of eventDays.value) if (!next.has(d)) next.set(d, 0)
  dayGuests.value = next
}

const clampGuests = (n: number): number =>
  Math.max(0, Math.min(PLUS_ONES_MAX, n))

function setDayGuests(date: string, count: number): void {
  if (!dayGuests.value.has(date)) return
  const next = new Map(dayGuests.value)
  next.set(date, clampGuests(count))
  dayGuests.value = next
}

function adjustDayGuests(date: string, delta: number): void {
  setDayGuests(date, (dayGuests.value.get(date) ?? 0) + delta)
}

// Quick-set: nudge the guest count on every selected day at once.
function adjustAllGuests(delta: number): void {
  const next = new Map<string, number>()
  for (const [date, count] of dayGuests.value) {
    next.set(date, clampGuests(count + delta))
  }
  dayGuests.value = next
}

// Rows for the per-day guest steppers, in date order.
const guestRows = computed(() =>
  selectedDays.value.map((date) => ({
    date,
    label: formatDateDisplay(date),
    guests: dayGuests.value.get(date) ?? 0,
  }))
)

const totalPickerGuests = computed(() =>
  [...dayGuests.value.values()].reduce((sum, n) => sum + n, 0)
)

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
  const n = selectedDays.value.length
  const total = eventDays.value.length
  if (n === 0) return 'Pick at least one day'
  if (n === total) return `Whole event (${total} days)`
  return `${n} of ${total} days`
})

const canSaveDays = computed(() => selectedDays.value.length > 0)

const dayPickerTitle = computed(() =>
  dayPickerUserId.value == null
    ? 'Your attendance days'
    : `Attendance days for ${memberName(dayPickerUserId.value)}`
)

async function handleSaveDays(): Promise<void> {
  const days = selectedDays.value
  if (days.length === 0) return
  // Selecting every day with no guests is just "the whole event" — send null so
  // it's stored canonically, matching the server's normalization. A guest on
  // any day keeps the day set materialized (null can't carry guest counts).
  const isWholeEvent =
    days.length === eventDays.value.length && totalPickerGuests.value === 0
  const attendance: AttendanceEntry[] | null = isWholeEvent
    ? null
    : days.map((date) => {
        const guests = dayGuests.value.get(date) ?? 0
        return guests > 0 ? { date, plusOnes: guests } : date
      })
  try {
    await rsvpsStore.submitRsvp(props.event.id, true, {
      attendance,
      onBehalfOfUserId: dayPickerUserId.value ?? undefined,
    })
    showDayPicker.value = false
  } catch {
    // Error handled by store
  }
}
</script>

<template>
  <section data-testid="rsvp-section">
    <BaseCard padded>
      <!-- Current user RSVP toggle -->
      <div class="mb-6">
        <p class="text-ink mb-2 text-sm font-medium">Your response</p>

        <div class="flex gap-2">
          <button
            type="button"
            data-testid="rsvp-attend"
            :aria-pressed="currentUserRsvp?.attending ? 'true' : 'false'"
            class="focus-visible:outline-focus inline-flex cursor-pointer items-center gap-2 rounded-md px-4 py-2 text-sm font-semibold shadow-sm transition-colors focus-visible:outline-2 focus-visible:outline-offset-2"
            :class="
              currentUserRsvp?.attending
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
              currentUserRsvp && !currentUserRsvp.attending ? 'true' : 'false'
            "
            class="focus-visible:outline-focus inline-flex cursor-pointer items-center gap-2 rounded-md px-4 py-2 text-sm font-semibold shadow-sm transition-colors focus-visible:outline-2 focus-visible:outline-offset-2"
            :class="
              currentUserRsvp && !currentUserRsvp.attending
                ? 'bg-red-600 text-white'
                : 'bg-btn-secondary-fill text-btn-secondary-ink hover:bg-btn-secondary-fill-hover'
            "
            @click="handleDecline"
          >
            <XCircleIcon class="size-4" aria-hidden="true" />
            Not Attending
          </button>
        </div>

        <!-- Partial attendance -->
        <div v-if="currentUserRsvp?.attending" class="mt-4">
          <div
            v-if="currentUserRsvp.attendance && isPartialDays(currentUserRsvp)"
            class="text-ink-muted mb-2 flex items-start gap-1.5 text-sm"
            data-testid="rsvp-attendance-days"
          >
            <CalendarDaysIcon class="mt-0.5 size-4 shrink-0" />
            <span>
              {{ attendanceSummary(currentUserRsvp) }}
              <span class="text-ink-muted">(partial)</span>
            </span>
          </div>
          <div
            v-else-if="
              !currentUserRsvp.attendance &&
              currentUserRsvp.startDate &&
              currentUserRsvp.endDate
            "
            class="text-ink-muted mb-2 flex items-center gap-1.5 text-sm"
          >
            <CalendarDaysIcon class="size-4 shrink-0" />
            <DateRangeDisplay
              :start-date="currentUserRsvp.startDate"
              :end-date="currentUserRsvp.endDate"
            />
            <span class="text-ink-muted">(partial)</span>
          </div>
          <div
            v-if="guestCountFor(currentUserRsvp) > 0"
            class="text-ink-muted mb-2 flex items-center gap-1.5 text-sm"
            data-testid="rsvp-attendance-guests"
          >
            <UserPlusIcon class="size-4 shrink-0" />
            <span>{{ guestSummary(currentUserRsvp) }}</span>
          </div>
          <TextButton
            v-if="!showDayPicker"
            data-testid="rsvp-change-dates"
            @click="openDayPicker"
          >
            {{ isPartialRsvp(currentUserRsvp) ? 'Change days' : 'Choose days' }}
          </TextButton>
        </div>
      </div>

      <!-- Day picker modal — shared by self-RSVP and on-behalf flows -->
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

        <!-- Per-day guests -->
        <div v-if="selectedDays.length > 0" class="mt-5">
          <div class="mb-2 flex items-center justify-between">
            <span class="text-ink text-sm font-medium">Guests per day</span>
            <div class="flex items-center gap-1">
              <button
                type="button"
                data-testid="rsvp-guests-all-decrement"
                class="bg-btn-secondary-fill text-btn-secondary-ink hover:bg-btn-secondary-fill-hover focus-visible:outline-focus flex size-8 cursor-pointer items-center justify-center rounded-md transition-colors focus-visible:outline-2 focus-visible:outline-offset-2"
                aria-label="Fewer guests on all days"
                @click="adjustAllGuests(-1)"
              >
                −
              </button>
              <span class="text-ink-muted px-1 text-xs">all days</span>
              <button
                type="button"
                data-testid="rsvp-guests-all-increment"
                class="bg-btn-secondary-fill text-btn-secondary-ink hover:bg-btn-secondary-fill-hover focus-visible:outline-focus flex size-8 cursor-pointer items-center justify-center rounded-md transition-colors focus-visible:outline-2 focus-visible:outline-offset-2"
                aria-label="More guests on all days"
                @click="adjustAllGuests(1)"
              >
                +
              </button>
            </div>
          </div>
          <ul class="divide-line-faint max-h-44 divide-y overflow-y-auto">
            <li
              v-for="row in guestRows"
              :key="row.date"
              class="flex items-center justify-between py-1.5 text-sm"
            >
              <span class="text-ink-muted">{{ row.label }}</span>
              <div
                class="flex items-center gap-1"
                :data-testid="`rsvp-day-guests-${row.date}`"
              >
                <button
                  type="button"
                  :data-testid="`rsvp-guest-decrement-${row.date}`"
                  class="bg-btn-secondary-fill text-btn-secondary-ink enabled:hover:bg-btn-secondary-fill-hover focus-visible:outline-focus flex size-8 cursor-pointer items-center justify-center rounded-md transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 disabled:cursor-not-allowed disabled:opacity-40"
                  :disabled="row.guests === 0"
                  :aria-label="`Fewer guests on ${row.label}`"
                  @click="adjustDayGuests(row.date, -1)"
                >
                  −
                </button>
                <span
                  class="text-ink min-w-[2.25rem] text-center font-mono tabular-nums"
                  :data-testid="`rsvp-guest-count-${row.date}`"
                >
                  +{{ row.guests }}
                </span>
                <button
                  type="button"
                  :data-testid="`rsvp-guest-increment-${row.date}`"
                  class="bg-btn-secondary-fill text-btn-secondary-ink enabled:hover:bg-btn-secondary-fill-hover focus-visible:outline-focus flex size-8 cursor-pointer items-center justify-center rounded-md transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 disabled:cursor-not-allowed disabled:opacity-40"
                  :disabled="row.guests >= PLUS_ONES_MAX"
                  :aria-label="`More guests on ${row.label}`"
                  @click="adjustDayGuests(row.date, 1)"
                >
                  +
                </button>
              </div>
            </li>
          </ul>
        </div>

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

      <!-- Attendee lists -->
      <div class="space-y-4">
        <!-- Attending -->
        <div v-if="attending.length > 0">
          <h3 class="text-state-success-ink mb-2 text-sm font-medium">
            Attending ({{ attending.length }})
          </h3>
          <ul class="space-y-2">
            <li
              v-for="rsvp in attending"
              :key="rsvp.id"
              class="bg-state-success-fill flex items-center gap-3 rounded-md px-3 py-2"
            >
              <div
                class="flex size-8 items-center justify-center rounded-full bg-green-200 dark:bg-green-800"
              >
                <CheckCircleIcon class="text-state-success-ink size-4" />
              </div>
              <div class="min-w-0 flex-1">
                <span class="text-ink">
                  {{ rsvp.member?.name || rsvp.member?.email || 'Unknown' }}
                  <span
                    v-if="rsvp.userId === currentUserId"
                    class="text-state-success-ink text-sm"
                  >
                    (you)
                  </span>
                  <span
                    v-if="filedByLabel(rsvp)"
                    class="text-ink-muted text-sm"
                    data-testid="rsvp-filed-by"
                  >
                    (RSVP'd by {{ filedByLabel(rsvp) }})
                  </span>
                </span>
                <p
                  v-if="rsvp.attendance && isPartialDays(rsvp)"
                  class="text-ink-muted text-xs"
                >
                  {{ attendanceSummary(rsvp) }}
                </p>
                <p
                  v-else-if="!rsvp.attendance && rsvp.startDate && rsvp.endDate"
                  class="text-ink-muted text-xs"
                >
                  <DateRangeDisplay
                    :start-date="rsvp.startDate"
                    :end-date="rsvp.endDate"
                  />
                </p>
                <p
                  v-if="guestCountFor(rsvp) > 0"
                  class="text-ink-muted text-xs"
                  data-testid="rsvp-attendee-guests"
                >
                  {{ guestSummary(rsvp) }}
                </p>
              </div>
              <RsvpActionsMenu
                v-if="rsvp.userId !== currentUserId"
                :menu-label="`Manage RSVP for ${rsvp.member?.name ?? 'member'}`"
                :actions="actionsFor(rsvp)"
                @pick="handlePick(rsvp.userId, $event)"
              />
            </li>
          </ul>
        </div>

        <!-- Not attending -->
        <div v-if="notAttending.length > 0">
          <h3 class="text-state-danger-ink mb-2 text-sm font-medium">
            Not Attending ({{ notAttending.length }})
          </h3>
          <ul class="space-y-2">
            <li
              v-for="rsvp in notAttending"
              :key="rsvp.id"
              class="bg-state-danger-fill flex items-center gap-3 rounded-md px-3 py-2"
            >
              <div
                class="flex size-8 items-center justify-center rounded-full bg-red-200 dark:bg-red-800"
              >
                <XCircleIcon class="text-state-danger-ink size-4" />
              </div>
              <span class="text-ink min-w-0 flex-1">
                {{ rsvp.member?.name || rsvp.member?.email || 'Unknown' }}
                <span
                  v-if="rsvp.userId === currentUserId"
                  class="text-state-danger-ink text-sm"
                >
                  (you)
                </span>
                <span
                  v-if="filedByLabel(rsvp)"
                  class="text-ink-muted text-sm"
                  data-testid="rsvp-filed-by"
                >
                  (RSVP'd by {{ filedByLabel(rsvp) }})
                </span>
              </span>
              <RsvpActionsMenu
                v-if="rsvp.userId !== currentUserId"
                :menu-label="`Manage RSVP for ${rsvp.member?.name ?? 'member'}`"
                :actions="actionsFor(rsvp)"
                @pick="handlePick(rsvp.userId, $event)"
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
                :actions="actionsFor(null)"
                @pick="handlePick(member.userId, $event)"
              />
            </li>
          </ul>
        </div>

        <!-- Summary -->
        <p v-if="event.rsvps.length > 0" class="text-ink-muted text-sm">
          {{ attending.length }} attending<span v-if="totalAttendingGuests > 0">
            (+{{ totalAttendingGuests }} guest{{
              totalAttendingGuests === 1 ? '' : 's'
            }})</span
          >, {{ notAttending.length }} not attending, {{ noResponse.length }}
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
          <template v-if="declineBlocked?.type === 'self'">
            You have expenses on this event. Delete your expenses before
            changing your RSVP to not attending.
          </template>
          <template v-else-if="declineBlocked?.type === 'other'">
            {{ declineBlocked.name }} has expenses on this event. Delete those
            expenses before marking them as not attending.
          </template>
        </p>
        <div class="mt-6 flex justify-end gap-3">
          <TextButton variant="secondary" @click="declineBlocked = null">
            Cancel
          </TextButton>
          <AppButton
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
