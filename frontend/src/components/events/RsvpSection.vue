<script setup lang="ts">
import { computed, ref } from 'vue'
import { CheckCircleIcon, XCircleIcon } from '@heroicons/vue/24/solid'
import {
  UserIcon,
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

const showPartialPicker = ref(false)
const partialStartDate = ref<string | null>(null)
const partialEndDate = ref<string | null>(null)
const hoverDate = ref<string | null>(null)
// Subject of the partial-date picker. `null` means current user (the
// existing self-RSVP flow); set to another user id when an admin is filing
// partial dates on someone else's behalf.
const partialPickerUserId = ref<string | null>(null)
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
    await rsvpsStore.submitRsvp(
      props.event.id,
      attending,
      null,
      null,
      userId === props.currentUserId ? undefined : userId
    )
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
  rsvp: { attending: boolean; startDate: string | null } | null
): RsvpAction[] {
  if (rsvp == null) {
    return [
      { kind: 'attend', label: 'Mark as attending' },
      { kind: 'decline', label: 'Mark as not attending', danger: true },
    ]
  }
  if (rsvp.attending) {
    return [
      rsvp.startDate
        ? { kind: 'change-dates', label: 'Change dates' }
        : { kind: 'set-dates', label: 'Set partial dates' },
      { kind: 'decline', label: 'Mark as not attending', danger: true },
    ]
  }
  return [{ kind: 'attend', label: 'Mark as attending' }]
}

function handlePick(userId: string, kind: RsvpActionKind): void {
  if (kind === 'attend') setRsvpFor(userId, true)
  else if (kind === 'decline') setRsvpFor(userId, false)
  else openPartialPicker(userId)
}

function openPartialPicker(forUserId?: string): void {
  const targetUserId = forUserId ?? props.currentUserId ?? null
  partialPickerUserId.value =
    targetUserId === props.currentUserId ? null : targetUserId
  const rsvp = targetUserId == null ? undefined : findRsvpFor(targetUserId)
  partialStartDate.value = rsvp?.startDate ?? null
  partialEndDate.value = rsvp?.endDate ?? null
  hoverDate.value = null

  // Navigate to the month of the event start
  if (props.event.startDate) {
    const [y, m] = props.event.startDate.split('-').map(Number) as [
      number,
      number,
    ]
    calYear.value = y
    calMonth.value = m - 1
  }
  showPartialPicker.value = true
}

function handleCalendarSelect(dateString: string): void {
  if (!partialStartDate.value || partialEndDate.value) {
    partialStartDate.value = dateString
    partialEndDate.value = null
  } else {
    let start = partialStartDate.value
    let end = dateString
    if (dateString < partialStartDate.value) {
      start = dateString
      end = partialStartDate.value
    }
    partialStartDate.value = start
    partialEndDate.value = end
  }
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

const partialSelectionText = computed(() => {
  if (partialStartDate.value && partialEndDate.value) {
    return `${formatDateDisplay(partialStartDate.value)} — ${formatDateDisplay(partialEndDate.value)}`
  }
  if (partialStartDate.value) {
    return `${formatDateDisplay(partialStartDate.value)} — pick end date`
  }
  return 'Pick your first day'
})

const canSavePartial = computed(
  () => !!partialStartDate.value && !!partialEndDate.value
)

const partialPickerTitle = computed(() =>
  partialPickerUserId.value == null
    ? 'Your attendance dates'
    : `Attendance dates for ${memberName(partialPickerUserId.value)}`
)

async function handleSavePartialDates(): Promise<void> {
  if (!partialStartDate.value || !partialEndDate.value) return
  try {
    await rsvpsStore.submitRsvp(
      props.event.id,
      true,
      partialStartDate.value,
      partialEndDate.value,
      partialPickerUserId.value ?? undefined
    )
    showPartialPicker.value = false
  } catch {
    // Error handled by store
  }
}

async function handleClearPartialDates(): Promise<void> {
  try {
    await rsvpsStore.submitRsvp(
      props.event.id,
      true,
      null,
      null,
      partialPickerUserId.value ?? undefined
    )
    showPartialPicker.value = false
  } catch {
    // Error handled by store
  }
}

const partialPickerRsvp = computed(() => {
  if (partialPickerUserId.value == null) return currentUserRsvp.value
  return findRsvpFor(partialPickerUserId.value)
})
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
            v-if="currentUserRsvp.startDate && currentUserRsvp.endDate"
            class="text-ink-muted mb-2 flex items-center gap-1.5 text-sm"
          >
            <CalendarDaysIcon class="size-4 shrink-0" />
            <DateRangeDisplay
              :start-date="currentUserRsvp.startDate"
              :end-date="currentUserRsvp.endDate"
            />
            <span class="text-ink-muted">(partial)</span>
          </div>
          <TextButton
            v-if="!showPartialPicker"
            data-testid="rsvp-change-dates"
            @click="openPartialPicker"
          >
            {{
              currentUserRsvp.startDate ? 'Change dates' : 'Set partial dates'
            }}
          </TextButton>
        </div>
      </div>

      <!-- Partial date picker modal — shared by self-RSVP and on-behalf flows -->
      <BaseModal
        :open="showPartialPicker"
        :title="partialPickerTitle"
        size="sm"
        @close="showPartialPicker = false"
      >
        <div class="text-ink-muted mb-4 text-sm">
          {{ partialSelectionText }}
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
          :selected-start="partialStartDate"
          :selected-end="partialEndDate"
          :hover-date="hoverDate"
          :min-date="event.startDate ?? undefined"
          :max-date="event.endDate ?? undefined"
          @select="handleCalendarSelect"
          @hover="hoverDate = $event"
        />

        <div class="mt-6 flex items-center justify-between">
          <div>
            <TextButton
              v-if="partialPickerRsvp?.startDate"
              variant="secondary"
              @click="handleClearPartialDates"
            >
              Attend full event
            </TextButton>
          </div>
          <div class="flex items-center gap-3">
            <TextButton variant="secondary" @click="showPartialPicker = false">
              Cancel
            </TextButton>
            <AppButton
              :disabled="!canSavePartial"
              @click="handleSavePartialDates"
            >
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
                  v-if="rsvp.startDate && rsvp.endDate"
                  class="text-ink-muted text-xs"
                >
                  <DateRangeDisplay
                    :start-date="rsvp.startDate"
                    :end-date="rsvp.endDate"
                  />
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
          {{ attending.length }} attending, {{ notAttending.length }} not
          attending, {{ noResponse.length }} pending
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
