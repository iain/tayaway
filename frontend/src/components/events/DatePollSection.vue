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
import {
  isPollOpen,
  isPollExpired,
  isPollResolved,
  canClosePoll,
  formatPollDeadline,
  rankDateRanges,
} from '@/utils/poll'
import VoteSummaryBar from '@/components/votes/VoteSummaryBar.vue'
import VoteBreakdown from '@/components/votes/VoteBreakdown.vue'
import ClosePollModal from './ClosePollModal.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'
import BaseCard from '@/components/common/BaseCard.vue'
import DateRangeDisplay from '@/components/common/DateRangeDisplay.vue'
import AppButton from '@/components/common/AppButton.vue'

const props = defineProps<{
  event: HydratedEvent
  isOwner: boolean
  currentUserId: string | null
}>()

const emit = defineEmits<{
  vote: []
}>()

const datePollsStore = useDatePollsStore()

const showClosePollModal = ref(false)

const poll = computed(() => props.event.datePoll)

const rankedDateRanges = computed(() =>
  poll.value ? rankDateRanges(poll.value.dateRanges) : []
)

const deadlineText = computed(() =>
  poll.value ? formatPollDeadline(poll.value.deadline) : ''
)

// Check current user vote status across poll date ranges
const currentUserVoteStatus = computed(() => {
  if (!poll.value || !props.currentUserId) return { voted: 0, total: 0 }
  const total = poll.value.dateRanges.length
  let voted = 0
  for (const dr of poll.value.dateRanges) {
    if (dr.votes.some((v) => v.userId === props.currentUserId)) {
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
  <section>
    <SectionHeading :icon="CalendarIcon" title="Date Poll" />
    <BaseCard padded>
      <template v-if="poll">
        <!-- Status bar -->
        <div
          class="mb-4 flex items-center justify-between rounded-md px-3 py-2"
          :class="{
            'bg-state-success-fill': isPollOpen(poll),
            'bg-state-warning-fill': isPollExpired(poll),
            'bg-state-info-fill': isPollResolved(poll),
          }"
        >
          <div class="flex items-center gap-2">
            <ClockIcon
              v-if="isPollOpen(poll)"
              class="text-state-success-ink size-4"
            />
            <ClockIcon
              v-else-if="isPollExpired(poll)"
              class="text-state-warning-ink size-4"
            />
            <CheckCircleSolidIcon v-else class="text-state-info-ink size-4" />
            <span
              class="text-sm font-medium"
              :class="{
                'text-state-success-ink': isPollOpen(poll),
                'text-state-warning-ink': isPollExpired(poll),
                'text-state-info-ink': isPollResolved(poll),
              }"
            >
              <template v-if="isPollOpen(poll)">
                {{ deadlineText }}
              </template>
              <template v-else-if="isPollExpired(poll)">
                Deadline passed - awaiting winner selection
              </template>
              <template v-else> Winner selected </template>
            </span>
          </div>
        </div>

        <!-- Vote CTA (when poll is open and has date ranges) -->
        <div
          v-if="isPollOpen(poll) && rankedDateRanges.length > 0"
          class="mb-4"
        >
          <AppButton size="lg" class="w-full sm:w-auto" @click="handleVote">
            <HandThumbUpIcon class="size-6" />
            Vote on Dates
          </AppButton>
          <p
            v-if="currentUserVoteStatus.total > 0"
            class="text-ink-muted mt-2 text-sm"
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
          <p class="text-ink-muted">No date ranges have been added yet.</p>
        </div>

        <div v-else class="space-y-3">
          <div
            v-for="(dateRange, index) in rankedDateRanges"
            :key="dateRange.id"
            class="rounded-md border p-4"
            :class="{
              'bg-state-info-fill border-blue-300 dark:border-blue-700':
                isPollResolved(poll) &&
                dateRange.id === poll.selectedDateRangeId,
              'bg-state-success-fill border-green-300 dark:border-green-700':
                !isPollResolved(poll) &&
                index === 0 &&
                dateRange.voteSummary.yes > 0,
              'border-line': !isPollResolved(poll)
                ? index !== 0 || dateRange.voteSummary.yes === 0
                : dateRange.id !== poll.selectedDateRangeId,
              'opacity-50':
                isPollResolved(poll) &&
                dateRange.id !== poll.selectedDateRangeId,
            }"
          >
            <div class="mb-2 flex items-center justify-between">
              <span class="text-ink font-medium">
                <span
                  v-if="
                    isPollResolved(poll) &&
                    dateRange.id === poll.selectedDateRangeId
                  "
                  class="text-state-info-ink mr-2"
                >
                  Winner
                </span>
                <span
                  v-else-if="index === 0 && dateRange.voteSummary.yes > 0"
                  class="text-state-success-ink mr-2"
                >
                  #1
                </span>
                <DateRangeDisplay
                  :start-date="dateRange.startDate"
                  :end-date="dateRange.endDate"
                />
              </span>
              <span class="text-ink-muted text-sm">
                {{ dateRange.voteSummary.total }}
                {{ dateRange.voteSummary.total === 1 ? 'vote' : 'votes' }}
              </span>
            </div>
            <VoteSummaryBar :summary="dateRange.voteSummary" />
            <VoteBreakdown
              :votes="dateRange.votes"
              :members="event.workspace?.members ?? []"
              class="border-line-faint mt-3 border-t pt-3"
            />
          </div>
        </div>

        <!-- Owner actions -->
        <div
          v-if="isOwner && canClosePoll(poll, rankedDateRanges.length)"
          class="mt-4"
        >
          <AppButton @click="handleClosePoll">Select Winner</AppButton>
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
  </section>
</template>
