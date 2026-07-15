<script setup lang="ts">
import { computed, ref } from 'vue'
import { CheckCircleIcon } from '@heroicons/vue/24/solid'
import { HomeIcon } from '@heroicons/vue/24/outline'
import { usePollsNeedingAttention } from '@/composables/usePollsNeedingAttention'
import { useEventsNeedingRsvp } from '@/composables/useEventsNeedingRsvp'
import { useUpcomingEvents } from '@/composables/useUpcomingEvents'
import { useUpcomingChores } from '@/composables/useUpcomingChores'
import { useEventsList } from '@/composables/useEventsList'
import { storeToRefs } from 'pinia'
import {
  useAuthStore,
  useMembersStore,
  useObjectPoolStore,
  useWorkspaceStore,
} from '@/stores'
import PageHeader from '@/components/common/PageHeader.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import { daysUntilBirthday, UPCOMING_BIRTHDAY_WINDOW_DAYS } from '@/utils/date'
import TodayBirthdays from '@/components/home/TodayBirthdays.vue'
import UpcomingBirthdays from '@/components/home/UpcomingBirthdays.vue'
import OpenSettlementsSection from '@/components/home/OpenSettlementsSection.vue'
import HappeningNowSection from '@/components/home/HappeningNowSection.vue'
import UpcomingChoresSection from '@/components/home/UpcomingChoresSection.vue'
import ChorePushBanner from '@/components/home/ChorePushBanner.vue'
import PastEventsOpenExpenses from '@/components/home/PastEventsOpenExpenses.vue'
import PollsNeedingAttention from '@/components/home/PollsNeedingAttention.vue'
import UpcomingEventsSection from '@/components/home/UpcomingEventsSection.vue'
import WelcomeSection from '@/components/home/WelcomeSection.vue'
import CreateEventWizard from '@/components/events/CreateEventWizard.vue'

const pool = useObjectPoolStore()
const authStore = useAuthStore()
const workspaceStore = useWorkspaceStore()
const { pollsNeedingAttention } = usePollsNeedingAttention()
const { eventsNeedingRsvp } = useEventsNeedingRsvp()
const { upcomingEvents } = useUpcomingEvents()
const {
  upcomingChores,
  visibleChores,
  hiddenCount: choresHiddenCount,
} = useUpcomingChores()
const { currentEvents, pastEvents, hasEvents } = useEventsList()

// Set of event ids the current user still owes an RSVP — surfaced as a badge
// on both happening-now and upcoming event cards.
const eventIdsNeedingRsvp = computed(
  () => new Set(eventsNeedingRsvp.value.map((e) => e.eventId))
)

const currentUserId = computed(() => authStore.currentUserId)
const { user } = storeToRefs(authStore)

const showEventModal = ref(false)

const isNewUser = computed(() => {
  return !hasEvents.value && pool.getAll('taskList').length === 0
})

const myUnpaidTransfers = computed(() => {
  const uid = currentUserId.value
  if (!uid) return []
  return pool
    .getAll('settlementTransfer')
    .filter(
      (t) =>
        t.paidAt === null &&
        !t.supersededAt &&
        (t.fromUserId === uid || t.toUserId === uid)
    )
})

const transfersOwedToYou = computed(() =>
  myUnpaidTransfers.value.filter((t) => t.toUserId === currentUserId.value)
)

const transfersYouOwe = computed(() =>
  myUnpaidTransfers.value.filter((t) => t.fromUserId === currentUserId.value)
)

// Precompute attendee counts by event ID — O(attendances) instead of
// O(events * attendances). Going guests count too: they eat and sleep.
const attendeeCountByEvent = computed<Map<string, number>>(() => {
  const counts = new Map<string, number>()
  for (const a of pool.getAll('attendance')) {
    if (a.status === 'going') {
      counts.set(a.eventId, (counts.get(a.eventId) ?? 0) + 1)
    }
  }
  return counts
})

// Precompute unsettled expense counts by event ID — O(expenses) instead of O(events * expenses)
const unsettledExpenseCountByEvent = computed<Map<string, number>>(() => {
  const counts = new Map<string, number>()
  for (const e of pool.getAll('expense')) {
    if (!e.settlementId) {
      counts.set(e.eventId, (counts.get(e.eventId) ?? 0) + 1)
    }
  }
  return counts
})

// Precompute unpaid transfer counts by event ID — O(settlements + transfers) instead of O(events * (settlements + transfers))
const unpaidTransferCountByEvent = computed<Map<string, number>>(() => {
  // Build a map from settlementId -> eventId in one pass
  const eventBySettlement = new Map<string, string>()
  for (const s of pool.getAll('settlement')) {
    eventBySettlement.set(s.id, s.eventId)
  }
  const counts = new Map<string, number>()
  for (const t of pool.getAll('settlementTransfer')) {
    if (!t.paidAt && !t.supersededAt) {
      const eventId = eventBySettlement.get(t.settlementId)
      if (eventId) {
        counts.set(eventId, (counts.get(eventId) ?? 0) + 1)
      }
    }
  }
  return counts
})

const pastEventsWithOpenExpenses = computed(() =>
  pastEvents.value.filter(
    (e) =>
      (unsettledExpenseCountByEvent.value.get(e.id) ?? 0) > 0 ||
      (unpaidTransferCountByEvent.value.get(e.id) ?? 0) > 0
  )
)

const { members } = storeToRefs(useMembersStore())

const todayBirthdays = computed(() =>
  members.value.filter((member) => daysUntilBirthday(member.birthday) === 0)
)

const upcomingBirthdays = computed(() =>
  members.value
    .filter((member) => {
      const days = daysUntilBirthday(member.birthday)
      return days !== null && days > 0 && days <= UPCOMING_BIRTHDAY_WINDOW_DAYS
    })
    .sort(
      (a, b) => daysUntilBirthday(a.birthday)! - daysUntilBirthday(b.birthday)!
    )
)

const hasBirthdays = computed(
  () => todayBirthdays.value.length > 0 || upcomingBirthdays.value.length > 0
)

const allCaughtUp = computed(
  () =>
    !isNewUser.value &&
    !hasBirthdays.value &&
    myUnpaidTransfers.value.length === 0 &&
    currentEvents.value.length === 0 &&
    upcomingChores.value.length === 0 &&
    upcomingEvents.value.length === 0 &&
    pastEventsWithOpenExpenses.value.length === 0 &&
    pollsNeedingAttention.value.length === 0
)
</script>

<template>
  <div>
    <PageHeader title="Dashboard" data-testid="page-title" :icon="HomeIcon" />

    <WelcomeSection
      v-if="isNewUser"
      :workspace-name="
        workspaceStore.currentWorkspace?.name ?? 'your workspace'
      "
      :user-name="user?.name ?? null"
      :member-count="members.length"
      :has-events="hasEvents"
      @create-event="showEventModal = true"
    />

    <EmptyState
      v-else-if="allCaughtUp"
      :icon="CheckCircleIcon"
      heading="Nice work — nothing needs your attention."
      description="You're all caught up. Enjoy the quiet."
    />

    <div v-else class="flex flex-col gap-8">
      <TodayBirthdays
        v-if="todayBirthdays.length > 0"
        :members="todayBirthdays"
      />

      <UpcomingBirthdays
        v-if="upcomingBirthdays.length > 0"
        :members="upcomingBirthdays"
      />

      <OpenSettlementsSection
        v-if="myUnpaidTransfers.length > 0"
        :transfers-owed-to-you="transfersOwedToYou"
        :transfers-you-owe="transfersYouOwe"
        :has-iban="!!user?.iban"
      />

      <HappeningNowSection
        v-if="currentEvents.length > 0"
        :events="currentEvents"
        :attendee-count-by-event="attendeeCountByEvent"
        :unpaid-transfer-count-by-event="unpaidTransferCountByEvent"
        :event-ids-needing-rsvp="eventIdsNeedingRsvp"
      />

      <template v-if="upcomingChores.length > 0">
        <ChorePushBanner />
        <UpcomingChoresSection
          :chores="visibleChores"
          :hidden-count="choresHiddenCount"
        />
      </template>

      <UpcomingEventsSection
        v-if="upcomingEvents.length > 0"
        :events="upcomingEvents"
      />

      <PastEventsOpenExpenses
        v-if="pastEventsWithOpenExpenses.length > 0"
        :events="pastEventsWithOpenExpenses"
        :unsettled-expense-count-by-event="unsettledExpenseCountByEvent"
        :unpaid-transfer-count-by-event="unpaidTransferCountByEvent"
      />

      <PollsNeedingAttention
        v-if="pollsNeedingAttention.length > 0"
        :polls="pollsNeedingAttention"
      />
    </div>

    <CreateEventWizard :open="showEventModal" @close="showEventModal = false" />
  </div>
</template>
