<script setup lang="ts">
import { ref, computed } from 'vue'
import {
  CalendarIcon,
  ClockIcon,
  CheckCircleIcon as CheckCircleSolidIcon,
} from '@heroicons/vue/24/solid'
import { HandThumbUpIcon } from '@heroicons/vue/24/outline'
import { useDatePollsStore } from '@/stores/datePolls'
import type { HydratedEvent } from '@/composables/useHydratedEvent'
import VoteSummaryBar from '@/components/votes/VoteSummaryBar.vue'
import ClosePollModal from './ClosePollModal.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'
import BaseCard from '@/components/common/BaseCard.vue'
import DateRangeDisplay from '@/components/common/DateRangeDisplay.vue'
import PrimaryButton from '@/components/common/PrimaryButton.vue'

const props = defineProps<{
  event: HydratedEvent
  isOwner: boolean
  currentMemberId: string | null
}>()

const emit = defineEmits<{
  vote: []
}>()

const datePollsStore = useDatePollsStore()

const showClosePollModal = ref(false)

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

function handleVote(): void {
  emit('vote')
}
</script>

<template>
  <BaseCard as="section" padded>
    <SectionHeading :icon="CalendarIcon" title="Date Poll" />

    <template v-if="poll">
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

      <!-- Vote CTA (when poll is open and has date ranges) -->
      <div
        v-if="poll.status === 'open' && rankedDateRanges.length > 0"
        class="mb-4"
      >
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
          class="mt-2 text-sm text-gray-500 dark:text-stone-400"
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
        <p class="text-gray-500 dark:text-stone-400">
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
            'border-gray-200 dark:border-stone-700':
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
              <DateRangeDisplay
                :start-date="dateRange.startDate"
                :end-date="dateRange.endDate"
              />
            </span>
            <span class="text-sm text-gray-500 dark:text-stone-400">
              {{ dateRange.voteSummary.total }}
              {{ dateRange.voteSummary.total === 1 ? 'vote' : 'votes' }}
            </span>
          </div>
          <VoteSummaryBar :summary="dateRange.voteSummary" />
        </div>
      </div>

      <!-- Owner actions -->
      <div
        v-if="
          isOwner &&
          rankedDateRanges.length > 0 &&
          (poll.status === 'open' || poll.status === 'expired')
        "
        class="mt-4"
      >
        <PrimaryButton @click="handleClosePoll">Select Winner</PrimaryButton>
      </div>
    </template>

    <!-- Modals -->
    <ClosePollModal
      :open="showClosePollModal"
      :date-ranges="rankedDateRanges"
      :loading="datePollsStore.loading"
      @confirm="handleClosePollConfirm"
      @close="showClosePollModal = false"
    />
  </BaseCard>
</template>
