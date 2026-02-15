<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { ChevronDownIcon, ChevronUpIcon } from '@heroicons/vue/24/outline'
import type { VoteResponse } from '@/types/pool'
import type { HydratedDateRange } from '@/composables/useHydratedEvent'
import { useCalendar } from '@/composables/useCalendar'
import { useVotesStore } from '@/stores/votes'
import VoteSummaryBar from './VoteSummaryBar.vue'
import VotersList from './VotersList.vue'
import FormTextarea from '@/components/form/FormTextarea.vue'

const props = defineProps<{
  dateRange: HydratedDateRange
  eventId: string
  currentMemberId: string | null
}>()

const { formatDateDisplay } = useCalendar()
const votesStore = useVotesStore()

const loading = ref(false)
const showVoters = ref(false)
const comment = ref('')
const showCommentInput = ref(false)

const currentUserVote = computed(() => {
  if (!props.currentMemberId) return null
  return (
    props.dateRange.votes.find((v) => v.memberId === props.currentMemberId) ??
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
  if (!props.currentMemberId) return

  loading.value = true
  try {
    await votesStore.submitVote(
      props.eventId,
      props.dateRange.id,
      response,
      currentUserVote.value?.comment || undefined
    )
  } finally {
    loading.value = false
  }
}

async function handleCommentSubmit() {
  if (!currentUserVote.value || !props.currentMemberId) return

  const voteResponse = currentUserVote.value.response
  const originalComment = currentUserVote.value.comment || ''
  const newComment = comment.value || undefined

  loading.value = true
  try {
    await votesStore.submitVote(
      props.eventId,
      props.dateRange.id,
      voteResponse,
      newComment
    )
  } catch {
    // Restore original comment in input on real failure
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
  <div class="rounded-lg bg-white p-4 shadow dark:bg-stone-800">
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
        <div class="mt-3 border-t border-gray-200 pt-3 dark:border-stone-700">
          <button
            type="button"
            class="flex items-center gap-1 text-sm text-cyan-600 underline hover:text-cyan-700 dark:text-cyan-400 dark:hover:text-cyan-300"
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
        class="flex-1 md:border-l md:border-gray-200 md:pl-6 md:dark:border-stone-700"
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
                : 'bg-gray-100 text-gray-700 hover:bg-green-100 hover:text-green-700 dark:bg-stone-700 dark:text-stone-300 dark:hover:bg-green-900/30 dark:hover:text-green-400',
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
                : 'bg-gray-100 text-gray-700 hover:bg-yellow-100 hover:text-yellow-700 dark:bg-stone-700 dark:text-stone-300 dark:hover:bg-yellow-900/30 dark:hover:text-yellow-400',
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
                : 'bg-gray-100 text-gray-700 hover:bg-red-100 hover:text-red-700 dark:bg-stone-700 dark:text-stone-300 dark:hover:bg-red-900/30 dark:hover:text-red-400',
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
            class="text-sm text-cyan-600 underline hover:text-cyan-700 dark:text-cyan-400 dark:hover:text-cyan-300"
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
                  : 'cursor-not-allowed bg-gray-200 text-gray-400 dark:bg-stone-700 dark:text-stone-500',
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
