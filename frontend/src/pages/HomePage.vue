<script setup lang="ts">
import { computed, ref } from 'vue'
import { useRouter } from 'vue-router'
import {
  BanknotesIcon,
  CakeIcon,
  CalendarDaysIcon,
  CheckCircleIcon,
  ClockIcon,
  InboxIcon,
  QrCodeIcon,
  UserGroupIcon,
} from '@heroicons/vue/24/outline'
import {
  usePollsNeedingAttention,
  formatDeadline,
  isUrgent,
  isPastDeadline,
} from '@/composables/usePollsNeedingAttention'
import {
  useEventsNeedingRsvp,
  formatEventDateRange,
} from '@/composables/useEventsNeedingRsvp'
import { useEventsList } from '@/composables/useEventsList'
import { storeToRefs } from 'pinia'
import { useAuthStore, useMembersStore, useObjectPoolStore } from '@/stores'
import { useSettlementsStore } from '@/stores/settlements'
import PageHeader from '@/components/common/PageHeader.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import { formatBirthday } from '@/utils/date'
import { formatAmount } from '@/utils/format'
import { getInitials, getMemberName } from '@/utils/member'
import DateRangeDisplay from '@/components/common/DateRangeDisplay.vue'
import EpcQrModal from '@/components/expenses/EpcQrModal.vue'
import type { PoolMember, PoolSettlementTransfer } from '@/types/pool'
import BaseCard from '@/components/common/BaseCard.vue'
import AppBadge from '@/components/common/AppBadge.vue'
import AppAvatar from '@/components/common/AppAvatar.vue'
import AlertBox from '@/components/common/AlertBox.vue'

const router = useRouter()
const pool = useObjectPoolStore()
const authStore = useAuthStore()
const settlementsStore = useSettlementsStore()
const { pollsNeedingAttention } = usePollsNeedingAttention()
const { eventsNeedingRsvp } = useEventsNeedingRsvp()
const { currentEvents, pastEvents } = useEventsList()

const currentUserId = computed(() => authStore.currentUserId)
const { user } = storeToRefs(authStore)

const myUnpaidTransfers = computed(() => {
  void pool.version
  const uid = currentUserId.value
  if (!uid) return []
  return pool
    .getAll('settlementTransfer')
    .filter(
      (t) => t.paidAt === null && (t.fromUserId === uid || t.toUserId === uid)
    )
})

const transfersOwedToYou = computed(() =>
  myUnpaidTransfers.value.filter((t) => t.toUserId === currentUserId.value)
)

const transfersYouOwe = computed(() =>
  myUnpaidTransfers.value.filter((t) => t.fromUserId === currentUserId.value)
)

function getEventNameForTransfer(transfer: PoolSettlementTransfer): string {
  const settlement = pool.get('settlement', transfer.settlementId)
  if (!settlement) return 'Unknown event'
  const event = pool.get('event', settlement.eventId)
  return event?.name ?? 'Unknown event'
}

function getEventIdForTransfer(
  transfer: PoolSettlementTransfer
): string | null {
  const settlement = pool.get('settlement', transfer.settlementId)
  if (!settlement) return null
  return settlement.eventId
}

const markingPaidIds = ref(new Set<string>())

async function handleMarkPaid(transferId: string) {
  if (markingPaidIds.value.has(transferId)) return
  markingPaidIds.value.add(transferId)
  try {
    await settlementsStore.markTransferPaid(transferId, true)
  } finally {
    markingPaidIds.value.delete(transferId)
  }
}

const showQrModal = ref(false)
const qrTransferId = ref<string | null>(null)
const qrRecipientName = ref<string | null>(null)
const qrAmount = ref<number | null>(null)

function memberHasIban(userId: string | null): boolean {
  if (!userId) return false
  return pool.findBy('member', 'userId', userId)?.hasIban ?? false
}

function openQrModal(transfer: PoolSettlementTransfer) {
  if (!transfer.toUserId) return
  const member = pool.findBy('member', 'userId', transfer.toUserId)
  if (!member?.hasIban) return
  qrTransferId.value = transfer.id
  qrRecipientName.value = member.name ?? member.email
  qrAmount.value = transfer.amount
  showQrModal.value = true
}

// Precompute attendee counts by event ID — O(rsvps) instead of O(events * rsvps)
const attendeeCountByEvent = computed<Map<string, number>>(() => {
  void pool.version
  const counts = new Map<string, number>()
  for (const r of pool.getAll('rsvp')) {
    if (r.attending) {
      counts.set(r.eventId, (counts.get(r.eventId) ?? 0) + 1)
    }
  }
  return counts
})

// Precompute unsettled expense counts by event ID — O(expenses) instead of O(events * expenses)
const unsettledExpenseCountByEvent = computed<Map<string, number>>(() => {
  void pool.version
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
  void pool.version
  // Build a map from settlementId -> eventId in one pass
  const eventBySettlement = new Map<string, string>()
  for (const s of pool.getAll('settlement')) {
    eventBySettlement.set(s.id, s.eventId)
  }
  const counts = new Map<string, number>()
  for (const t of pool.getAll('settlementTransfer')) {
    if (!t.paidAt) {
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

function birthdayMonthDay(member: PoolMember): [number, number] | null {
  if (!member.birthday) return null
  const [, month, day] = member.birthday.split('-')
  return [Number(month), Number(day)]
}

const todayBirthdays = computed(() => {
  const today = new Date()
  const m = today.getMonth() + 1
  const d = today.getDate()
  return members.value.filter((member) => {
    const md = birthdayMonthDay(member)
    return md && md[0] === m && md[1] === d
  })
})

const upcomingBirthdays = computed(() => {
  const today = new Date()
  const todayM = today.getMonth() + 1
  const todayD = today.getDate()

  return members.value
    .filter((member) => {
      const md = birthdayMonthDay(member)
      if (!md) return false
      // Exclude today's birthdays
      if (md[0] === todayM && md[1] === todayD) return false
      // Check if birthday falls within the next 7 days
      for (let i = 1; i <= 7; i++) {
        const future = new Date(today)
        future.setDate(future.getDate() + i)
        if (md[0] === future.getMonth() + 1 && md[1] === future.getDate()) {
          return true
        }
      }
      return false
    })
    .sort((a, b) => {
      const amd = birthdayMonthDay(a)!
      const bmd = birthdayMonthDay(b)!
      return amd[0] - bmd[0] || amd[1] - bmd[1]
    })
})

function formatBirthdayDate(member: PoolMember): string {
  if (!member.birthday) return ''
  const today = new Date()
  const [, month, day] = member.birthday.split('-')
  for (let i = 1; i <= 7; i++) {
    const future = new Date(today)
    future.setDate(future.getDate() + i)
    if (
      Number(month) === future.getMonth() + 1 &&
      Number(day) === future.getDate()
    ) {
      if (i === 1) return 'Tomorrow'
      return future.toLocaleDateString(undefined, {
        weekday: 'long',
      })
    }
  }
  return formatBirthday(member.birthday)
}

const hasBirthdays = computed(
  () => todayBirthdays.value.length > 0 || upcomingBirthdays.value.length > 0
)

const allCaughtUp = computed(
  () =>
    !hasBirthdays.value &&
    myUnpaidTransfers.value.length === 0 &&
    currentEvents.value.length === 0 &&
    pastEventsWithOpenExpenses.value.length === 0 &&
    pollsNeedingAttention.value.length === 0 &&
    eventsNeedingRsvp.value.length === 0
)

function navigateToEvent(eventId: string): void {
  router.push(`/events/${eventId}/planning/vote`)
}

function navigateToEventPage(eventId: string): void {
  router.push(`/events/${eventId}`)
}
</script>

<template>
  <div>
    <PageHeader title="Dashboard" data-testid="page-title" />

    <EmptyState
      v-if="allCaughtUp"
      :icon="CheckCircleIcon"
      heading="You're all caught up"
      description="Nothing needs your attention right now."
      icon-class="text-green-400 dark:text-green-500"
    />

    <template v-else>
      <!-- Today's birthdays -->
      <section v-if="todayBirthdays.length > 0">
        <h2 class="mb-4 text-lg font-medium text-gray-900 dark:text-white">
          🎂 Happy Birthday!
        </h2>

        <ul class="space-y-3">
          <li
            v-for="member in todayBirthdays"
            :key="member.id"
            class="birthday-card-dashboard overflow-hidden rounded-lg shadow"
          >
            <div class="flex items-center gap-4 px-4 py-4 sm:px-6">
              <div
                class="flex size-10 shrink-0 animate-bounce items-center justify-center rounded-full bg-amber-300 text-lg ring-4 ring-amber-400/50 dark:bg-amber-500 dark:ring-amber-500/50"
              >
                🎂
              </div>
              <div class="min-w-0 flex-1">
                <h3
                  class="truncate text-base font-semibold text-gray-900 dark:text-white"
                >
                  {{ member.name || member.email }}
                </h3>
                <p class="birthday-shimmer text-sm font-bold">
                  🎉 It's their birthday today! 🎉
                </p>
              </div>
              <span class="text-2xl">🥳</span>
            </div>
          </li>
        </ul>
      </section>

      <!-- Upcoming birthdays this week -->
      <section
        v-if="upcomingBirthdays.length > 0"
        :class="todayBirthdays.length > 0 ? 'mt-8' : ''"
      >
        <h2 class="mb-4 text-lg font-medium text-gray-900 dark:text-white">
          Upcoming birthdays
        </h2>

        <ul class="space-y-3">
          <BaseCard
            v-for="member in upcomingBirthdays"
            :key="member.id"
            as="li"
            class="overflow-hidden"
          >
            <div class="flex items-center gap-4 px-4 py-4 sm:px-6">
              <AppAvatar :initials="getInitials(member)" />
              <div class="min-w-0 flex-1">
                <h3
                  class="truncate text-base font-semibold text-gray-900 dark:text-white"
                >
                  {{ member.name || member.email }}
                </h3>
                <div
                  class="mt-0.5 flex items-center gap-1 text-sm text-gray-500 dark:text-stone-400"
                >
                  <CakeIcon class="size-4" />
                  {{ formatBirthdayDate(member) }}
                </div>
              </div>
            </div>
          </BaseCard>
        </ul>
      </section>

      <!-- Open settlements -->
      <section
        v-if="myUnpaidTransfers.length > 0"
        :class="hasBirthdays ? 'mt-8' : ''"
      >
        <h2 class="mb-1 text-lg font-medium text-gray-900 dark:text-white">
          Open settlements
        </h2>
        <p class="mb-4 text-sm text-gray-500 dark:text-stone-400">
          Mark a transfer as paid once you've received the payment.
        </p>

        <AlertBox
          v-if="transfersOwedToYou.length > 0 && !user?.iban"
          variant="warning"
          :icon="BanknotesIcon"
          class="mb-3"
        >
          <p class="text-sm">
            Add your IBAN so others can pay you with a single QR code scan.
          </p>
          <button
            type="button"
            class="mt-1 text-sm font-medium text-amber-700 underline hover:text-amber-900 dark:text-amber-400 dark:hover:text-amber-200"
            @click="router.push('/profile')"
          >
            Add IBAN in profile
          </button>
        </AlertBox>

        <ul class="space-y-3">
          <BaseCard
            v-for="transfer in transfersOwedToYou"
            :key="transfer.id"
            as="li"
            class="overflow-hidden"
          >
            <div
              class="flex flex-wrap items-center justify-between gap-y-2 px-4 py-3 sm:px-6"
            >
              <div class="min-w-0 flex-1">
                <p class="text-sm text-gray-900 dark:text-white">
                  <span class="font-semibold">{{
                    getMemberName(transfer.fromUserId, pool)
                  }}</span>
                  owes you
                  <span
                    class="font-mono font-semibold text-gray-900 dark:text-white"
                    >{{ formatAmount(transfer.amount) }}</span
                  >
                </p>
                <p class="mt-0.5 text-xs text-gray-500 dark:text-stone-400">
                  <router-link
                    v-if="getEventIdForTransfer(transfer)"
                    :to="`/events/${getEventIdForTransfer(transfer)}/expenses`"
                    class="hover:text-rose-600 hover:underline dark:hover:text-rose-400"
                  >
                    {{ getEventNameForTransfer(transfer) }}
                  </router-link>
                  <span v-else>{{ getEventNameForTransfer(transfer) }}</span>
                </p>
              </div>
              <button
                type="button"
                :disabled="markingPaidIds.has(transfer.id)"
                class="cursor-pointer rounded-md bg-gray-100 px-2 py-1 text-xs font-medium text-gray-600 transition-colors hover:bg-gray-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-rose-500 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-stone-700 dark:text-stone-300 dark:hover:bg-stone-600"
                @click="handleMarkPaid(transfer.id)"
              >
                {{
                  markingPaidIds.has(transfer.id) ? 'Marking...' : 'Mark paid'
                }}
              </button>
            </div>
          </BaseCard>
          <BaseCard
            v-for="transfer in transfersYouOwe"
            :key="transfer.id"
            as="li"
            variant="action"
            class="overflow-hidden"
          >
            <div
              class="flex flex-wrap items-center justify-between gap-y-2 px-4 py-3 sm:px-6"
            >
              <div class="min-w-0 flex-1">
                <p class="text-sm text-gray-700 dark:text-stone-300">
                  You owe
                  <span class="font-semibold text-gray-900 dark:text-white">{{
                    getMemberName(transfer.toUserId, pool)
                  }}</span>
                </p>
                <p
                  class="mt-0.5 font-mono text-lg font-bold text-amber-700 dark:text-amber-400"
                >
                  {{ formatAmount(transfer.amount) }}
                </p>
                <p class="mt-0.5 text-xs text-gray-500 dark:text-stone-400">
                  <router-link
                    v-if="getEventIdForTransfer(transfer)"
                    :to="`/events/${getEventIdForTransfer(transfer)}/expenses`"
                    class="hover:text-rose-600 hover:underline dark:hover:text-rose-400"
                  >
                    {{ getEventNameForTransfer(transfer) }}
                  </router-link>
                  <span v-else>{{ getEventNameForTransfer(transfer) }}</span>
                </p>
              </div>
              <button
                v-if="memberHasIban(transfer.toUserId)"
                type="button"
                class="cursor-pointer rounded-lg bg-amber-600 p-2 text-white shadow-sm transition-colors hover:bg-amber-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-amber-500 dark:bg-amber-600 dark:hover:bg-amber-500"
                title="Show QR code for bank transfer"
                @click="openQrModal(transfer)"
              >
                <QrCodeIcon class="size-5" />
              </button>
            </div>
          </BaseCard>
        </ul>
      </section>

      <section
        v-if="currentEvents.length > 0"
        data-testid="happening-now-section"
        :class="hasBirthdays || myUnpaidTransfers.length > 0 ? 'mt-8' : ''"
      >
        <h2 class="mb-4 text-lg font-medium text-gray-900 dark:text-white">
          Happening now
        </h2>

        <ul class="space-y-3">
          <BaseCard
            v-for="event in currentEvents"
            :key="event.id"
            as="li"
            class="overflow-hidden"
          >
            <div class="px-4 py-4 sm:px-6">
              <div
                class="cursor-pointer"
                role="button"
                tabindex="0"
                @click="navigateToEventPage(event.id)"
                @keydown.enter="navigateToEventPage(event.id)"
                @keydown.space.prevent="navigateToEventPage(event.id)"
              >
                <h3
                  class="truncate text-base font-semibold text-gray-900 dark:text-white"
                >
                  {{ event.name }}
                </h3>
                <div class="mt-1 flex flex-wrap items-center gap-3 text-sm">
                  <span
                    class="inline-flex items-center gap-1 text-gray-500 dark:text-stone-400"
                  >
                    <CalendarDaysIcon class="size-4" />
                    <DateRangeDisplay
                      :start-date="event.startDate!"
                      :end-date="event.endDate!"
                    />
                  </span>
                </div>
              </div>
              <div class="mt-3 flex flex-wrap gap-2">
                <router-link
                  :to="`/events/${event.id}/rsvp`"
                  class="inline-flex items-center gap-1.5 rounded-full bg-gray-100 px-3 py-1 text-sm font-medium text-gray-700 transition-colors hover:bg-rose-100 hover:text-rose-700 dark:bg-stone-700 dark:text-stone-300 dark:hover:bg-rose-900/30 dark:hover:text-rose-300"
                >
                  <UserGroupIcon class="size-4" />
                  {{ attendeeCountByEvent.get(event.id) ?? 0 }} attending
                </router-link>
                <router-link
                  v-if="(unpaidTransferCountByEvent.get(event.id) ?? 0) > 0"
                  :to="`/events/${event.id}/expenses`"
                  class="inline-flex items-center gap-1.5 rounded-full bg-gray-100 px-3 py-1 text-sm font-medium text-gray-700 transition-colors hover:bg-rose-100 hover:text-rose-700 dark:bg-stone-700 dark:text-stone-300 dark:hover:bg-rose-900/30 dark:hover:text-rose-300"
                >
                  <BanknotesIcon class="size-4" />
                  {{ unpaidTransferCountByEvent.get(event.id) ?? 0 }} unpaid
                </router-link>
              </div>
            </div>
          </BaseCard>
        </ul>
      </section>

      <section
        v-if="pastEventsWithOpenExpenses.length > 0"
        :class="
          currentEvents.length > 0 ||
          myUnpaidTransfers.length > 0 ||
          hasBirthdays
            ? 'mt-8'
            : ''
        "
      >
        <h2 class="mb-4 text-lg font-medium text-gray-900 dark:text-white">
          Past events with open expenses
        </h2>

        <ul class="space-y-3">
          <BaseCard
            v-for="event in pastEventsWithOpenExpenses"
            :key="event.id"
            as="li"
            class="overflow-hidden"
          >
            <div class="px-4 py-4 sm:px-6">
              <div
                class="cursor-pointer"
                role="button"
                tabindex="0"
                @click="navigateToEventPage(event.id)"
                @keydown.enter="navigateToEventPage(event.id)"
                @keydown.space.prevent="navigateToEventPage(event.id)"
              >
                <h3
                  class="truncate text-base font-semibold text-gray-900 dark:text-white"
                >
                  {{ event.name }}
                </h3>
                <div class="mt-1 flex flex-wrap items-center gap-3 text-sm">
                  <span
                    class="inline-flex items-center gap-1 text-gray-500 dark:text-stone-400"
                  >
                    <CalendarDaysIcon class="size-4" />
                    <DateRangeDisplay
                      :start-date="event.startDate!"
                      :end-date="event.endDate!"
                    />
                  </span>
                </div>
              </div>
              <div class="mt-3 flex flex-wrap gap-2">
                <router-link
                  v-if="(unsettledExpenseCountByEvent.get(event.id) ?? 0) > 0"
                  :to="`/events/${event.id}/expenses`"
                  class="inline-flex items-center gap-1.5 rounded-full bg-gray-100 px-3 py-1 text-sm font-medium text-gray-700 transition-colors hover:bg-rose-100 hover:text-rose-700 dark:bg-stone-700 dark:text-stone-300 dark:hover:bg-rose-900/30 dark:hover:text-rose-300"
                >
                  <BanknotesIcon class="size-4" />
                  {{
                    unsettledExpenseCountByEvent.get(event.id) ?? 0
                  }}
                  unsettled
                </router-link>
                <router-link
                  v-if="(unpaidTransferCountByEvent.get(event.id) ?? 0) > 0"
                  :to="`/events/${event.id}/expenses`"
                  class="inline-flex items-center gap-1.5 rounded-full bg-gray-100 px-3 py-1 text-sm font-medium text-gray-700 transition-colors hover:bg-rose-100 hover:text-rose-700 dark:bg-stone-700 dark:text-stone-300 dark:hover:bg-rose-900/30 dark:hover:text-rose-300"
                >
                  <BanknotesIcon class="size-4" />
                  {{ unpaidTransferCountByEvent.get(event.id) ?? 0 }} unpaid
                </router-link>
              </div>
            </div>
          </BaseCard>
        </ul>
      </section>

      <section
        v-if="pollsNeedingAttention.length > 0"
        :class="
          currentEvents.length > 0 ||
          pastEventsWithOpenExpenses.length > 0 ||
          myUnpaidTransfers.length > 0 ||
          hasBirthdays
            ? 'mt-8'
            : ''
        "
      >
        <h2 class="mb-4 text-lg font-medium text-gray-900 dark:text-white">
          Polls awaiting your vote
        </h2>

        <ul class="space-y-3">
          <BaseCard
            v-for="item in pollsNeedingAttention"
            :key="item.eventId"
            as="li"
            interactive
            :variant="
              isPastDeadline(item.deadline)
                ? 'urgent'
                : isUrgent(item.deadline)
                  ? 'action'
                  : undefined
            "
            class="overflow-hidden"
            @click="navigateToEvent(item.eventId)"
          >
            <div class="px-4 py-4 sm:px-6">
              <div class="flex items-center justify-between gap-3">
                <div class="min-w-0 flex-1">
                  <h3
                    class="truncate text-base font-semibold text-gray-900 dark:text-white"
                  >
                    {{ item.eventName }}
                  </h3>
                  <div class="mt-1 flex flex-wrap items-center gap-3 text-sm">
                    <span
                      class="inline-flex items-center gap-1"
                      :class="
                        isPastDeadline(item.deadline)
                          ? 'font-semibold text-red-600 dark:text-red-400'
                          : isUrgent(item.deadline)
                            ? 'font-medium text-amber-600 dark:text-amber-400'
                            : 'text-gray-500 dark:text-stone-400'
                      "
                    >
                      <ClockIcon class="size-4" />
                      {{ formatDeadline(item.deadline) }}
                    </span>
                    <span
                      class="inline-flex items-center gap-1 text-gray-500 dark:text-stone-400"
                    >
                      <InboxIcon class="size-4" />
                      Voted on {{ item.votedCount }} of
                      {{ item.totalCount }} date
                      {{ item.totalCount === 1 ? 'option' : 'options' }}
                    </span>
                  </div>
                </div>
                <AppBadge
                  v-if="isPastDeadline(item.deadline)"
                  variant="red"
                  size="sm"
                >
                  Overdue
                </AppBadge>
              </div>
            </div>
          </BaseCard>
        </ul>
      </section>

      <section
        v-if="eventsNeedingRsvp.length > 0"
        :class="
          pollsNeedingAttention.length > 0 ||
          pastEventsWithOpenExpenses.length > 0 ||
          currentEvents.length > 0 ||
          myUnpaidTransfers.length > 0 ||
          hasBirthdays
            ? 'mt-8'
            : ''
        "
      >
        <h2 class="mb-4 text-lg font-medium text-gray-900 dark:text-white">
          Events awaiting your RSVP
        </h2>

        <ul class="space-y-3">
          <BaseCard
            v-for="item in eventsNeedingRsvp"
            :key="item.eventId"
            as="li"
            interactive
            class="overflow-hidden"
            @click="navigateToEventPage(item.eventId)"
          >
            <div class="px-4 py-4 sm:px-6">
              <div class="flex items-center justify-between">
                <div class="min-w-0 flex-1">
                  <h3
                    class="truncate text-base font-semibold text-gray-900 dark:text-white"
                  >
                    {{ item.eventName }}
                  </h3>
                  <div class="mt-1 flex flex-wrap items-center gap-3 text-sm">
                    <span
                      class="inline-flex items-center gap-1 text-gray-500 dark:text-stone-400"
                    >
                      <CalendarDaysIcon class="size-4" />
                      {{ formatEventDateRange(item.startDate, item.endDate) }}
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </BaseCard>
        </ul>
      </section>
    </template>

    <EpcQrModal
      :open="showQrModal"
      :transfer-id="qrTransferId"
      :recipient-name="qrRecipientName"
      :amount="qrAmount"
      @close="showQrModal = false"
    />
  </div>
</template>

<style scoped>
.birthday-card-dashboard {
  background: linear-gradient(
    135deg,
    #fef3c7 0%,
    #fce7f3 25%,
    #ede9fe 50%,
    #dbeafe 75%,
    #fef3c7 100%
  );
  background-size: 300% 300%;
  animation: birthday-gradient 4s ease infinite;
}

:where(.dark) .birthday-card-dashboard {
  background: linear-gradient(
    135deg,
    #78350f 0%,
    #831843 25%,
    #4c1d95 50%,
    #1e3a5f 75%,
    #78350f 100%
  );
  background-size: 300% 300%;
  animation: birthday-gradient 4s ease infinite;
}

@keyframes birthday-gradient {
  0%,
  100% {
    background-position: 0% 50%;
  }
  50% {
    background-position: 100% 50%;
  }
}

.birthday-shimmer {
  background: linear-gradient(
    90deg,
    #f59e0b,
    #ec4899,
    #8b5cf6,
    #f59e0b,
    #ec4899
  );
  background-size: 200% auto;
  background-clip: text;
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  animation: birthday-shimmer-move 2s linear infinite;
}

@keyframes birthday-shimmer-move {
  to {
    background-position: 200% center;
  }
}
</style>
