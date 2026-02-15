<script setup lang="ts">
import { ref, computed } from 'vue'
import {
  CalendarIcon,
  ClockIcon,
  PlusIcon,
  CheckCircleIcon as CheckCircleSolidIcon,
} from '@heroicons/vue/24/solid'
import { HandThumbUpIcon } from '@heroicons/vue/24/outline'
import { useDatePollsStore } from '@/stores/datePolls'
import { useCalendar } from '@/composables/useCalendar'
import type { HydratedEvent } from '@/composables/useHydratedEvent'
import VoteSummaryBar from '@/components/votes/VoteSummaryBar.vue'
import DateRangeModal from './DateRangeModal.vue'
import OpenPollModal from './OpenPollModal.vue'
import ClosePollModal from './ClosePollModal.vue'

const props = defineProps<{
  event: HydratedEvent
  isOwner: boolean
  currentMemberId: string | null
}>()

const emit = defineEmits<{
  vote: []
}>()

const datePollsStore = useDatePollsStore()
const { formatDateDisplay, addDays } = useCalendar()

const showOpenPollModal = ref(false)
const showClosePollModal = ref(false)
const showDateRangeModal = ref(false)
const reopenMode = ref(false)
const modalPreselectedStart = ref<string | null>(null)
const modalPreselectedEnd = ref<string | null>(null)

const poll = computed(() => props.event.datePoll)

const rankedDateRanges = computed(() => {
  if (!poll.value) return []
  return [...poll.value.dateRanges].sort((a, b) => {
    if (b.voteSummary.yes !== a.voteSummary.yes) {
      return b.voteSummary.yes - a.voteSummary.yes
    }
    if (b.voteSummary.preferably_not !== a.voteSummary.preferably_not) {
      return b.voteSummary.preferably_not - a.voteSummary.preferably_not
    }
    return b.voteSummary.no - a.voteSummary.no
  })
})

const deadlineText = computed(() => {
  if (!poll.value) return ''
  const deadline = new Date(poll.value.deadline)
  const now = new Date()
  const diff = deadline.getTime() - now.getTime()

  if (diff <= 0) return 'Deadline passed'

  const days = Math.floor(diff / (1000 * 60 * 60 * 24))
  const hours = Math.floor((diff % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60))

  if (days > 0) return `${days}d ${hours}h remaining`
  if (hours > 0) return `${hours}h remaining`
  const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60))
  return `${minutes}m remaining`
})

// Check current user vote status across poll date ranges
const currentUserVoteStatus = computed(() => {
  if (!poll.value || !props.currentMemberId) return { voted: 0, total: 0 }
  const total = poll.value.dateRanges.length
  let voted = 0
  for (const dr of poll.value.dateRanges) {
    if (dr.votes.some((v) => v.memberId === props.currentMemberId)) {
      voted++
    }
  }
  return { voted, total }
})

function handleOpenPoll(): void {
  reopenMode.value = false
  showOpenPollModal.value = true
}

function handleReopenPoll(): void {
  reopenMode.value = true
  showOpenPollModal.value = true
}

async function handleOpenPollConfirm(deadline: string): Promise<void> {
  try {
    if (reopenMode.value) {
      await datePollsStore.reopenPoll(props.event.id, deadline)
    } else {
      await datePollsStore.createPoll(props.event.id, deadline)
    }
    showOpenPollModal.value = false
  } catch {
    // Error handled by store
  }
}

function handleClosePoll(): void {
  showClosePollModal.value = true
}

async function handleClosePollConfirm(dateRangeId: string): Promise<void> {
  try {
    await datePollsStore.closePoll(props.event.id, dateRangeId)
    showClosePollModal.value = false
  } catch {
    // Error handled by store
  }
}

function handleAddDateRange(): void {
  if (poll.value && poll.value.dateRanges.length > 0) {
    const sortedRanges = [...poll.value.dateRanges].sort((a, b) =>
      a.endDate.localeCompare(b.endDate)
    )
    const lastRange = sortedRanges[sortedRanges.length - 1]
    modalPreselectedStart.value = addDays(lastRange.startDate, 7)
    modalPreselectedEnd.value = addDays(lastRange.endDate, 7)
  } else {
    modalPreselectedStart.value = null
    modalPreselectedEnd.value = null
  }
  showDateRangeModal.value = true
}

async function handleDateRangeModalSave(
  startDate: string,
  endDate: string
): Promise<void> {
  try {
    await datePollsStore.addDateRange(props.event.id, startDate, endDate)
    showDateRangeModal.value = false
  } catch {
    // Error handled by store
  }
}

async function handleRemoveDateRange(dateRangeId: string): Promise<void> {
  try {
    await datePollsStore.removeDateRange(props.event.id, dateRangeId)
  } catch {
    // Error handled by store
  }
}

function handleVote(): void {
  emit('vote')
}
</script>

<template>
  <section class="rounded-lg bg-white p-6 shadow dark:bg-gray-800">
    <h2
      class="mb-4 flex items-center gap-2 text-lg font-semibold text-gray-900 dark:text-white"
    >
      <CalendarIcon class="size-5" />
      Date Poll
    </h2>

    <!-- No poll yet -->
    <div v-if="!poll" class="py-4 text-center">
      <p class="mb-4 text-gray-500 dark:text-gray-400">
        No date poll has been created yet.
      </p>
      <button
        v-if="isOwner"
        type="button"
        class="inline-flex items-center gap-2 rounded-md bg-rose-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-rose-500"
        @click="handleOpenPoll"
      >
        <CalendarIcon class="size-4" />
        Open Date Poll
      </button>
    </div>

    <!-- Poll exists -->
    <template v-else>
      <!-- Status bar -->
      <div
        class="mb-4 flex items-center justify-between rounded-md px-3 py-2"
        :class="{
          'bg-green-50 dark:bg-green-900/20': poll.status === 'open',
          'bg-amber-50 dark:bg-amber-900/20': poll.status === 'expired',
          'bg-blue-50 dark:bg-blue-900/20': poll.status === 'resolved',
        }"
      >
        <div class="flex items-center gap-2">
          <ClockIcon
            v-if="poll.status === 'open'"
            class="size-4 text-green-600 dark:text-green-400"
          />
          <ClockIcon
            v-else-if="poll.status === 'expired'"
            class="size-4 text-amber-600 dark:text-amber-400"
          />
          <CheckCircleSolidIcon
            v-else
            class="size-4 text-blue-600 dark:text-blue-400"
          />
          <span
            class="text-sm font-medium"
            :class="{
              'text-green-700 dark:text-green-300': poll.status === 'open',
              'text-amber-700 dark:text-amber-300': poll.status === 'expired',
              'text-blue-700 dark:text-blue-300': poll.status === 'resolved',
            }"
          >
            <template v-if="poll.status === 'open'">
              {{ deadlineText }}
            </template>
            <template v-else-if="poll.status === 'expired'">
              Deadline passed - awaiting winner selection
            </template>
            <template v-else> Winner selected </template>
          </span>
        </div>
      </div>

      <!-- Vote CTA (when poll is open) -->
      <div v-if="poll.status === 'open'" class="mb-4">
        <button
          type="button"
          class="inline-flex w-full items-center justify-center gap-2 rounded-lg bg-rose-600 px-6 py-4 text-lg font-semibold text-white shadow-sm hover:bg-rose-500 sm:w-auto"
          @click="handleVote"
        >
          <HandThumbUpIcon class="size-6" />
          Vote on Dates
        </button>
        <p
          v-if="currentUserVoteStatus.total > 0"
          class="mt-2 text-sm text-gray-500 dark:text-gray-400"
        >
          <template
            v-if="currentUserVoteStatus.voted === currentUserVoteStatus.total"
          >
            <CheckCircleSolidIcon class="inline size-4 text-green-500" />
            You've voted on all {{ currentUserVoteStatus.total }} date options
          </template>
          <template v-else>
            You've voted on {{ currentUserVoteStatus.voted }} of
            {{ currentUserVoteStatus.total }} date options
          </template>
        </p>
      </div>

      <!-- Date ranges list -->
      <div v-if="rankedDateRanges.length === 0" class="py-4 text-center">
        <p class="text-gray-500 dark:text-gray-400">
          No date ranges have been added yet.
        </p>
      </div>

      <div v-else class="space-y-3">
        <div
          v-for="(dateRange, index) in rankedDateRanges"
          :key="dateRange.id"
          class="rounded-md border p-4"
          :class="{
            'border-blue-300 bg-blue-50 dark:border-blue-700 dark:bg-blue-900/20':
              poll.status === 'resolved' &&
              dateRange.id === poll.selectedDateRangeId,
            'border-green-300 bg-green-50 dark:border-green-700 dark:bg-green-900/20':
              poll.status !== 'resolved' &&
              index === 0 &&
              dateRange.voteSummary.yes > 0,
            'border-gray-200 dark:border-gray-700':
              poll.status !== 'resolved'
                ? index !== 0 || dateRange.voteSummary.yes === 0
                : dateRange.id !== poll.selectedDateRangeId,
            'opacity-50':
              poll.status === 'resolved' &&
              dateRange.id !== poll.selectedDateRangeId,
          }"
        >
          <div class="mb-2 flex items-center justify-between">
            <span class="font-medium text-gray-900 dark:text-white">
              <span
                v-if="
                  poll.status === 'resolved' &&
                  dateRange.id === poll.selectedDateRangeId
                "
                class="mr-2 text-blue-600 dark:text-blue-400"
              >
                Winner
              </span>
              <span
                v-else-if="index === 0 && dateRange.voteSummary.yes > 0"
                class="mr-2 text-green-600 dark:text-green-400"
              >
                #1
              </span>
              {{ formatDateDisplay(dateRange.startDate) }}
              <span v-if="dateRange.startDate !== dateRange.endDate">
                - {{ formatDateDisplay(dateRange.endDate) }}
              </span>
            </span>
            <div class="flex items-center gap-2">
              <span class="text-sm text-gray-500 dark:text-gray-400">
                {{ dateRange.voteSummary.total }}
                {{ dateRange.voteSummary.total === 1 ? 'vote' : 'votes' }}
              </span>
              <button
                v-if="isOwner && poll.status === 'open'"
                type="button"
                class="text-sm text-red-500 hover:text-red-700 dark:hover:text-red-400"
                @click="handleRemoveDateRange(dateRange.id)"
              >
                Remove
              </button>
            </div>
          </div>
          <VoteSummaryBar :summary="dateRange.voteSummary" />
        </div>
      </div>

      <!-- Owner actions -->
      <div v-if="isOwner" class="mt-4 flex flex-wrap gap-2">
        <button
          v-if="poll.status === 'open'"
          type="button"
          class="inline-flex items-center gap-2 rounded-md bg-gray-100 px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-200 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-gray-600"
          @click="handleAddDateRange"
        >
          <PlusIcon class="size-4" />
          Add Date Range
        </button>
        <button
          v-if="poll.status === 'open' || poll.status === 'expired'"
          type="button"
          class="inline-flex items-center gap-2 rounded-md bg-rose-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-rose-500"
          @click="handleClosePoll"
        >
          Select Winner
        </button>
        <button
          v-if="poll.status === 'resolved'"
          type="button"
          class="inline-flex items-center gap-2 rounded-md bg-gray-100 px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-200 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-gray-600"
          @click="handleReopenPoll"
        >
          Reopen Poll
        </button>
      </div>
    </template>

    <!-- Modals -->
    <OpenPollModal
      :open="showOpenPollModal"
      :title="reopenMode ? 'Reopen Date Poll' : 'Open Date Poll'"
      :loading="datePollsStore.loading"
      @confirm="handleOpenPollConfirm"
      @close="showOpenPollModal = false"
    />

    <ClosePollModal
      :open="showClosePollModal"
      :date-ranges="rankedDateRanges"
      :loading="datePollsStore.loading"
      @confirm="handleClosePollConfirm"
      @close="showClosePollModal = false"
    />

    <DateRangeModal
      :open="showDateRangeModal"
      :preselected-start="modalPreselectedStart"
      :preselected-end="modalPreselectedEnd"
      @save="handleDateRangeModalSave"
      @close="showDateRangeModal = false"
    />
  </section>
</template>
