<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { ChevronDownIcon, ChevronUpIcon } from '@heroicons/vue/24/outline'
import type { User } from '@/types'
import type { PoolApiResponse, VoteResponse } from '@/types/pool'
import type { HydratedDateRange } from '@/composables/useHydratedEvent'
import { useCalendar } from '@/composables/useCalendar'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useOptimistic } from '@/composables/useOptimistic'
import { api } from '@/api/client'
import VoteSummaryBar from './VoteSummaryBar.vue'
import VotersList from './VotersList.vue'

const props = defineProps<{
  dateRange: HydratedDateRange
  eventId: string
  currentUser: User | null
}>()

const { formatDateDisplay } = useCalendar()
const pool = useObjectPoolStore()
const { execute } = useOptimistic()

const loading = ref(false)
const showVoters = ref(false)
const comment = ref('')
const showCommentInput = ref(false)

const currentUserVote = computed(() => {
  if (!props.currentUser) return null
  return props.dateRange.votes.find(v => v.userId === props.currentUser?.id) ?? null
})

// Initialize comment from existing vote and keep section open if comment exists
watch(currentUserVote, (vote) => {
  if (vote?.comment) {
    comment.value = vote.comment
    showCommentInput.value = true
  }
}, { immediate: true })

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
      await execute(
        'vote',
        existingVote.id,
        { response },
        () => api.post<PoolApiResponse>(
          `/events/${props.eventId}/votes`,
          {
            date_range_id: props.dateRange.id,
            response,
            comment: existingVote.comment || undefined,
          }
        )
      )
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

      // Optimistically update dateRange's voteIds
      const dateRange = pool.get('dateRange', props.dateRange.id)
      if (dateRange) {
        pool.addPending('dateRange', props.dateRange.id, {
          voteIds: [...dateRange.voteIds, voteId],
        })
      }

      try {
        await api.post<PoolApiResponse>(
          `/events/${props.eventId}/votes`,
          {
            id: voteId,
            date_range_id: props.dateRange.id,
            response,
          }
        )
        // Server response automatically imported by API client
      } catch {
        // Rollback: remove vote and restore dateRange
        pool.remove('vote', voteId)
        const serverDateRange = pool.getServer('dateRange', props.dateRange.id)
        if (serverDateRange) {
          pool.set(serverDateRange)
        }
        throw new Error('Failed to create vote')
      }
    }
  } finally {
    loading.value = false
  }
}

async function handleCommentSubmit() {
  if (!currentUserVote.value || !props.currentUser) return

  const vote = currentUserVote.value
  const originalComment = vote.comment || ''

  loading.value = true
  try {
    await execute(
      'vote',
      vote.id,
      { comment: comment.value || null },
      () => api.post<PoolApiResponse>(
        `/events/${props.eventId}/votes`,
        {
          date_range_id: props.dateRange.id,
          response: vote.response,
          comment: comment.value || undefined,
        }
      )
    )
  } catch {
    // Restore original comment in input on failure
    comment.value = originalComment
  } finally {
    loading.value = false
  }
}

function toggleCommentInput() {
  showCommentInput.value = !showCommentInput.value
}
</script>

<template>
  <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-4">
    <div class="flex flex-col md:flex-row md:gap-6">
      <!-- Left side: Date range info and stats -->
      <div class="flex-1 mb-4 md:mb-0">
        <h3 class="text-sm font-medium text-gray-900 dark:text-white mb-3">
          {{ formatDateDisplay(dateRange.startDate) }}
          <span v-if="dateRange.startDate !== dateRange.endDate">
            - {{ formatDateDisplay(dateRange.endDate) }}
          </span>
        </h3>

        <!-- Vote Summary -->
        <VoteSummaryBar :summary="dateRange.voteSummary" />

        <!-- Voters List Toggle -->
        <div class="mt-3 pt-3 border-t border-gray-200 dark:border-gray-700">
          <button
            type="button"
            class="flex items-center gap-1 text-sm text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white"
            @click="showVoters = !showVoters"
          >
            <component
              :is="showVoters ? ChevronUpIcon : ChevronDownIcon"
              class="size-4"
            />
            {{ showVoters ? 'Hide' : 'Show' }} votes ({{ dateRange.voteSummary.total }})
          </button>
          <div
            v-if="showVoters"
            class="mt-3"
          >
            <VotersList :votes="dateRange.votes" />
          </div>
        </div>
      </div>

      <!-- Right side: Voting elements -->
      <div class="flex-1 md:border-l md:border-gray-200 md:dark:border-gray-700 md:pl-6">
        <!-- Vote Buttons -->
        <div class="flex gap-2 mb-4">
          <button
            type="button"
            :disabled="loading"
            class="flex-1 px-3 py-2 text-sm font-medium rounded-md transition-colors"
            :class="[
              isSelected('yes')
                ? 'bg-green-600 text-white'
                : 'bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300 hover:bg-green-100 dark:hover:bg-green-900/30 hover:text-green-700 dark:hover:text-green-400'
            ]"
            @click="handleVote('yes')"
          >
            Yes
          </button>
          <button
            type="button"
            :disabled="loading"
            class="flex-1 px-3 py-2 text-sm font-medium rounded-md transition-colors"
            :class="[
              isSelected('preferably_not')
                ? 'bg-yellow-500 text-white'
                : 'bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300 hover:bg-yellow-100 dark:hover:bg-yellow-900/30 hover:text-yellow-700 dark:hover:text-yellow-400'
            ]"
            @click="handleVote('preferably_not')"
          >
            Preferably not
          </button>
          <button
            type="button"
            :disabled="loading"
            class="flex-1 px-3 py-2 text-sm font-medium rounded-md transition-colors"
            :class="[
              isSelected('no')
                ? 'bg-red-600 text-white'
                : 'bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300 hover:bg-red-100 dark:hover:bg-red-900/30 hover:text-red-700 dark:hover:text-red-400'
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
            class="text-sm text-indigo-600 dark:text-indigo-400 hover:underline"
            @click="toggleCommentInput"
          >
            {{ showCommentInput ? 'Hide comment' : (currentUserVote.comment ? 'Edit comment' : 'Add a comment') }}
          </button>
          <div
            v-if="showCommentInput"
            class="mt-2"
          >
            <textarea
              v-model="comment"
              placeholder="Optional comment..."
              rows="2"
              class="block w-full rounded-md bg-gray-100 dark:bg-gray-700 px-3 py-2 text-sm text-gray-900 dark:text-white placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:outline-none focus:ring-2 focus:ring-indigo-500"
            />
            <button
              type="button"
              :disabled="loading || !hasCommentChanges"
              class="mt-2 px-4 py-2 text-sm font-medium rounded-md transition-colors"
              :class="[
                hasCommentChanges
                  ? 'bg-indigo-600 text-white hover:bg-indigo-500 disabled:bg-indigo-400'
                  : 'bg-gray-200 dark:bg-gray-700 text-gray-400 dark:text-gray-500 cursor-not-allowed'
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
