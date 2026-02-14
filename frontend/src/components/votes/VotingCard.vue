<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { ChevronDownIcon, ChevronUpIcon } from '@heroicons/vue/24/outline'
import type { AuthUser } from '@/types'
import type { PoolApiResponse, VoteResponse } from '@/types/pool'
import type { HydratedDateRange } from '@/composables/useHydratedEvent'
import { useCalendar } from '@/composables/useCalendar'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useCommandQueueStore, CommandQueuedError } from '@/stores/commandQueue'
import { useOptimistic } from '@/composables/useOptimistic'
import VoteSummaryBar from './VoteSummaryBar.vue'
import VotersList from './VotersList.vue'
import FormTextarea from '@/components/form/FormTextarea.vue'

const props = defineProps<{
  dateRange: HydratedDateRange
  eventId: string
  currentUser: AuthUser | null
}>()

const { formatDateDisplay } = useCalendar()
const pool = useObjectPoolStore()
const commandQueue = useCommandQueueStore()
const { execute } = useOptimistic()

const loading = ref(false)
const showVoters = ref(false)
const comment = ref('')
const showCommentInput = ref(false)

const currentUserVote = computed(() => {
  if (!props.currentUser) return null
  return (
    props.dateRange.votes.find((v) => v.userId === props.currentUser?.id) ??
    null
  )
})

// Initialize comment from existing vote and keep section open if comment exists
watch(
  currentUserVote,
  (vote) => {
    if (vote?.comment) {
      comment.value = vote.comment
      showCommentInput.value = true
    }
  },
  { immediate: true }
)

const isSelected = computed(() => (response: VoteResponse) => {
  return currentUserVote.value?.response === response
})

const hasCommentChanges = computed(() => {
  if (!currentUserVote.value) return false
  return comment.value !== (currentUserVote.value.comment || '')
})

async function handleVote(response: VoteResponse) {
  if (!props.currentUser) return

  const existingVote = currentUserVote.value

  loading.value = true
  try {
    if (existingVote) {
      // Update existing vote using optimistic helper
      try {
        await execute('vote', existingVote.id, { response }, () =>
          commandQueue.enqueue<PoolApiResponse>(
            'POST',
            `/events/${props.eventId}/votes`,
            {
              date_range_id: props.dateRange.id,
              response,
              comment: existingVote.comment || undefined,
            }
          )
        )
      } catch (e) {
        if (!(e instanceof CommandQueuedError)) throw e
      }
    } else {
      // Create new vote with client-generated ID
      // Manual handling needed because we update multiple pool objects
      const voteId = crypto.randomUUID()

      // Optimistically add vote to pool
      pool.set({
        id: voteId,
        objectType: 'vote',
        dateRangeId: props.dateRange.id,
        userId: props.currentUser.id,
        response,
        comment: null,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      })

      try {
        await commandQueue.enqueue<PoolApiResponse>(
          'POST',
          `/events/${props.eventId}/votes`,
          {
            id: voteId,
            date_range_id: props.dateRange.id,
            response,
          }
        )
        // Server response automatically imported by API client
      } catch (e) {
        if (e instanceof CommandQueuedError) return
        // Rollback: remove optimistic vote from pool
        pool.remove('vote', voteId)
        throw new Error('Failed to create vote')
      }
    }
  } finally {
    loading.value = false
  }
}

async function handleCommentSubmit() {
  if (!currentUserVote.value || !props.currentUser) return

  // Capture all values at start to avoid stale closures during async operation
  const voteId = currentUserVote.value.id
  const voteResponse = currentUserVote.value.response
  const dateRangeId = props.dateRange.id
  const eventId = props.eventId
  const originalComment = currentUserVote.value.comment || ''
  const newComment = comment.value || null

  loading.value = true
  try {
    await execute('vote', voteId, { comment: newComment }, () =>
      commandQueue.enqueue<PoolApiResponse>(
        'POST',
        `/events/${eventId}/votes`,
        {
          date_range_id: dateRangeId,
          response: voteResponse,
          comment: newComment || undefined,
        }
      )
    )
  } catch (e) {
    if (!(e instanceof CommandQueuedError)) {
      // Restore original comment in input on real failure
      comment.value = originalComment
    }
  } finally {
    loading.value = false
  }
}

function toggleCommentInput() {
  showCommentInput.value = !showCommentInput.value
}
</script>

<template>
  <div class="rounded-lg bg-white p-4 shadow dark:bg-gray-800">
    <div class="flex flex-col md:flex-row md:gap-6">
      <!-- Left side: Date range info and stats -->
      <div class="mb-4 flex-1 md:mb-0">
        <h3 class="mb-3 text-sm font-medium text-gray-900 dark:text-white">
          {{ formatDateDisplay(dateRange.startDate) }}
          <span v-if="dateRange.startDate !== dateRange.endDate">
            - {{ formatDateDisplay(dateRange.endDate) }}
          </span>
        </h3>

        <!-- Vote Summary -->
        <VoteSummaryBar :summary="dateRange.voteSummary" />

        <!-- Voters List Toggle -->
        <div class="mt-3 border-t border-gray-200 pt-3 dark:border-gray-700">
          <button
            type="button"
            class="flex items-center gap-1 text-sm text-gray-600 hover:text-gray-900 dark:text-gray-400 dark:hover:text-white"
            @click="showVoters = !showVoters"
          >
            <component
              :is="showVoters ? ChevronUpIcon : ChevronDownIcon"
              class="size-4"
            />
            {{ showVoters ? 'Hide' : 'Show' }} votes ({{
              dateRange.voteSummary.total
            }})
          </button>
          <div v-if="showVoters" class="mt-3">
            <VotersList :votes="dateRange.votes" />
          </div>
        </div>
      </div>

      <!-- Right side: Voting elements -->
      <div
        class="flex-1 md:border-l md:border-gray-200 md:pl-6 md:dark:border-gray-700"
      >
        <!-- Vote Buttons -->
        <div class="mb-4 flex gap-2">
          <button
            type="button"
            :disabled="loading"
            class="flex-1 rounded-md px-3 py-2 text-sm font-medium transition-colors"
            :class="[
              isSelected('yes')
                ? 'bg-green-600 text-white'
                : 'bg-gray-100 text-gray-700 hover:bg-green-100 hover:text-green-700 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-green-900/30 dark:hover:text-green-400',
            ]"
            @click="handleVote('yes')"
          >
            Yes
          </button>
          <button
            type="button"
            :disabled="loading"
            class="flex-1 rounded-md px-3 py-2 text-sm font-medium transition-colors"
            :class="[
              isSelected('preferably_not')
                ? 'bg-yellow-500 text-white'
                : 'bg-gray-100 text-gray-700 hover:bg-yellow-100 hover:text-yellow-700 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-yellow-900/30 dark:hover:text-yellow-400',
            ]"
            @click="handleVote('preferably_not')"
          >
            Preferably not
          </button>
          <button
            type="button"
            :disabled="loading"
            class="flex-1 rounded-md px-3 py-2 text-sm font-medium transition-colors"
            :class="[
              isSelected('no')
                ? 'bg-red-600 text-white'
                : 'bg-gray-100 text-gray-700 hover:bg-red-100 hover:text-red-700 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-red-900/30 dark:hover:text-red-400',
            ]"
            @click="handleVote('no')"
          >
            No
          </button>
        </div>

        <!-- Comment Input (only show after user has voted) -->
        <div v-if="currentUserVote">
          <button
            type="button"
            class="text-sm text-rose-600 hover:underline dark:text-rose-400"
            @click="toggleCommentInput"
          >
            {{
              showCommentInput
                ? 'Hide comment'
                : currentUserVote.comment
                  ? 'Edit comment'
                  : 'Add a comment'
            }}
          </button>
          <div v-if="showCommentInput" class="mt-2">
            <FormTextarea
              :id="`comment-${dateRange.id}`"
              v-model="comment"
              label="Comment"
              placeholder="Optional comment..."
              :rows="2"
            />
            <button
              type="button"
              :disabled="loading || !hasCommentChanges"
              class="mt-2 rounded-md px-4 py-2 text-sm font-medium transition-colors"
              :class="[
                hasCommentChanges
                  ? 'bg-rose-600 text-white hover:bg-rose-500 disabled:bg-rose-400'
                  : 'cursor-not-allowed bg-gray-200 text-gray-400 dark:bg-gray-700 dark:text-gray-500',
              ]"
              @click="handleCommentSubmit"
            >
              {{ loading ? 'Saving...' : 'Save comment' }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
