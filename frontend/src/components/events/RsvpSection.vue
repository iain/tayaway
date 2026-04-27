<script setup lang="ts">
import { computed, ref } from 'vue'
import {
  CheckCircleIcon,
  XCircleIcon,
  UserGroupIcon,
} from '@heroicons/vue/24/solid'
import {
  UserIcon,
  CalendarDaysIcon,
  ChevronLeftIcon,
  ChevronRightIcon,
} from '@heroicons/vue/24/outline'
import { useRsvpsStore } from '@/stores/rsvps'
import { useObjectPoolStore } from '@/stores/objectPool'
import type { HydratedEvent } from '@/composables/useHydratedEvent'
import { useCalendar } from '@/composables/useCalendar'
import SectionHeading from '@/components/common/SectionHeading.vue'
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

const showPartialPicker = ref(false)
const showExpensesDialog = ref(false)
const partialStartDate = ref<string | null>(null)
const partialEndDate = ref<string | null>(null)
const hoverDate = ref<string | null>(null)

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

const userHasExpenses = computed(() => {
  if (!props.currentUserId) return false
  return pool
    .getAll('expense')
    .some(
      (e) => e.eventId === props.event.id && e.userId === props.currentUserId
    )
})

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

async function handleDecline(): Promise<void> {
  if (userHasExpenses.value) {
    showExpensesDialog.value = true
    return
  }
  try {
    await rsvpsStore.submitRsvp(props.event.id, false)
  } catch {
    // Error handled by store
  }
}

function openPartialPicker(): void {
  const rsvp = currentUserRsvp.value
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

async function handleSavePartialDates(): Promise<void> {
  if (!partialStartDate.value || !partialEndDate.value) return
  try {
    await rsvpsStore.submitRsvp(
      props.event.id,
      true,
      partialStartDate.value,
      partialEndDate.value
    )
    showPartialPicker.value = false
  } catch {
    // Error handled by store
  }
}

async function handleClearPartialDates(): Promise<void> {
  try {
    await rsvpsStore.submitRsvp(props.event.id, true)
    showPartialPicker.value = false
  } catch {
    // Error handled by store
  }
}
</script>

<template>
  <BaseCard as="section" padded data-testid="rsvp-section">
    <SectionHeading :icon="UserGroupIcon" title="RSVPs" />

    <!-- Current user RSVP toggle -->
    <div class="mb-6">
      <p class="mb-2 text-sm font-medium text-gray-700 dark:text-stone-300">
        Your response
      </p>

      <div class="flex gap-2">
        <button
          type="button"
          data-testid="rsvp-attend"
          :aria-pressed="currentUserRsvp?.attending ? 'true' : 'false'"
          class="inline-flex cursor-pointer items-center gap-2 rounded-md px-4 py-2 text-sm font-semibold shadow-sm transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-rose-500"
          :class="
            currentUserRsvp?.attending
              ? 'bg-green-600 text-white'
              : 'bg-gray-100 text-gray-700 hover:bg-gray-200 dark:bg-stone-700 dark:text-stone-300 dark:hover:bg-stone-600'
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
          class="inline-flex cursor-pointer items-center gap-2 rounded-md px-4 py-2 text-sm font-semibold shadow-sm transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-rose-500"
          :class="
            currentUserRsvp && !currentUserRsvp.attending
              ? 'bg-red-600 text-white'
              : 'bg-gray-100 text-gray-700 hover:bg-gray-200 dark:bg-stone-700 dark:text-stone-300 dark:hover:bg-stone-600'
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
          class="mb-2 flex items-center gap-1.5 text-sm text-gray-600 dark:text-stone-400"
        >
          <CalendarDaysIcon class="size-4 shrink-0" />
          <DateRangeDisplay
            :start-date="currentUserRsvp.startDate"
            :end-date="currentUserRsvp.endDate"
          />
          <span class="text-gray-400 dark:text-stone-500">(partial)</span>
        </div>
        <TextButton
          v-if="!showPartialPicker"
          data-testid="rsvp-change-dates"
          @click="openPartialPicker"
        >
          {{ currentUserRsvp.startDate ? 'Change dates' : 'Set partial dates' }}
        </TextButton>

        <!-- Partial date picker modal -->
        <BaseModal
          :open="showPartialPicker"
          title="Your attendance dates"
          size="sm"
          @close="showPartialPicker = false"
        >
          <div class="mb-4 text-sm text-gray-500 dark:text-stone-400">
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
                v-if="currentUserRsvp?.startDate"
                variant="secondary"
                @click="handleClearPartialDates"
              >
                Attend full event
              </TextButton>
            </div>
            <div class="flex items-center gap-3">
              <TextButton
                variant="secondary"
                @click="showPartialPicker = false"
              >
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
      </div>
    </div>

    <!-- Attendee lists -->
    <div class="space-y-4">
      <!-- Attending -->
      <div v-if="attending.length > 0">
        <h3 class="mb-2 text-sm font-medium text-green-600 dark:text-green-400">
          Attending ({{ attending.length }})
        </h3>
        <ul class="space-y-2">
          <li
            v-for="rsvp in attending"
            :key="rsvp.id"
            class="flex items-center gap-3 rounded-md bg-green-50 px-3 py-2 dark:bg-green-900/20"
          >
            <div
              class="flex size-8 items-center justify-center rounded-full bg-green-200 dark:bg-green-800"
            >
              <CheckCircleIcon
                class="size-4 text-green-600 dark:text-green-400"
              />
            </div>
            <div>
              <span class="text-gray-900 dark:text-white">
                {{ rsvp.member?.name || rsvp.member?.email || 'Unknown' }}
                <span
                  v-if="rsvp.userId === currentUserId"
                  class="text-sm text-green-600 dark:text-green-400"
                >
                  (you)
                </span>
                <span
                  v-if="filedByLabel(rsvp)"
                  class="text-sm text-gray-500 dark:text-stone-400"
                  data-testid="rsvp-filed-by"
                >
                  (RSVP'd by {{ filedByLabel(rsvp) }})
                </span>
              </span>
              <p
                v-if="rsvp.startDate && rsvp.endDate"
                class="text-xs text-gray-500 dark:text-stone-400"
              >
                <DateRangeDisplay
                  :start-date="rsvp.startDate"
                  :end-date="rsvp.endDate"
                />
              </p>
            </div>
          </li>
        </ul>
      </div>

      <!-- Not attending -->
      <div v-if="notAttending.length > 0">
        <h3 class="mb-2 text-sm font-medium text-red-600 dark:text-red-400">
          Not Attending ({{ notAttending.length }})
        </h3>
        <ul class="space-y-2">
          <li
            v-for="rsvp in notAttending"
            :key="rsvp.id"
            class="flex items-center gap-3 rounded-md bg-red-50 px-3 py-2 dark:bg-red-900/20"
          >
            <div
              class="flex size-8 items-center justify-center rounded-full bg-red-200 dark:bg-red-800"
            >
              <XCircleIcon class="size-4 text-red-600 dark:text-red-400" />
            </div>
            <span class="text-gray-900 dark:text-white">
              {{ rsvp.member?.name || rsvp.member?.email || 'Unknown' }}
              <span
                v-if="rsvp.userId === currentUserId"
                class="text-sm text-red-600 dark:text-red-400"
              >
                (you)
              </span>
              <span
                v-if="filedByLabel(rsvp)"
                class="text-sm text-gray-500 dark:text-stone-400"
                data-testid="rsvp-filed-by"
              >
                (RSVP'd by {{ filedByLabel(rsvp) }})
              </span>
            </span>
          </li>
        </ul>
      </div>

      <!-- No response -->
      <div v-if="noResponse.length > 0">
        <h3 class="mb-2 text-sm font-medium text-gray-500 dark:text-stone-400">
          No Response ({{ noResponse.length }})
        </h3>
        <ul class="space-y-2">
          <li
            v-for="member in noResponse"
            :key="member.id"
            class="flex items-center gap-3 rounded-md bg-gray-50 px-3 py-2 dark:bg-stone-700/50"
          >
            <div
              class="flex size-8 items-center justify-center rounded-full bg-gray-200 dark:bg-stone-600"
            >
              <UserIcon class="size-4 text-gray-500 dark:text-stone-400" />
            </div>
            <span class="text-gray-900 dark:text-white">
              {{ member.name || member.email || 'Unknown' }}
              <span
                v-if="member.userId === currentUserId"
                class="text-sm text-amber-600 dark:text-amber-400"
              >
                (you)
              </span>
            </span>
          </li>
        </ul>
      </div>

      <!-- Summary -->
      <p
        v-if="event.rsvps.length > 0"
        class="text-sm text-gray-500 dark:text-stone-400"
      >
        {{ attending.length }} attending, {{ notAttending.length }} not
        attending, {{ noResponse.length }} pending
      </p>
    </div>

    <BaseModal
      :open="showExpensesDialog"
      title="Cannot decline"
      size="sm"
      @close="showExpensesDialog = false"
    >
      <p class="text-sm text-gray-600 dark:text-stone-400">
        You have expenses on this event. Delete your expenses before changing
        your RSVP to not attending.
      </p>
      <div class="mt-6 flex justify-end gap-3">
        <TextButton variant="secondary" @click="showExpensesDialog = false">
          Cancel
        </TextButton>
        <AppButton
          :to="`/events/${event.id}/expenses`"
          autofocus
          @click="showExpensesDialog = false"
        >
          Go to Expenses
        </AppButton>
      </div>
    </BaseModal>
  </BaseCard>
</template>
