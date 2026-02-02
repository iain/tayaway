<script setup lang="ts">
import { ref, computed } from 'vue'
import { ChevronDownIcon, ChevronUpIcon } from '@heroicons/vue/24/outline'
import type { DateRange, VoteResponse, User } from '@/types'
import { useCalendar } from '@/composables/useCalendar'
import { useVotes } from '@/composables/useVotes'
import VoteSummaryBar from './VoteSummaryBar.vue'
import VotersList from './VotersList.vue'

const props = defineProps<{
  dateRange: DateRange
  eventId: string
  currentUser: User | null
}>()

const emit = defineEmits<{
  voteUpdated: []
}>()

const { formatDateDisplay } = useCalendar()
const { submitVote, loading } = useVotes()

const showVoters = ref(false)
const comment = ref('')
const showCommentInput = ref(false)

const currentUserVote = computed(() => {
  if (!props.currentUser) return null
  return props.dateRange.votes.find(v => v.user_id === props.currentUser?.id) ?? null
})

const isSelected = computed(() => (response: VoteResponse) => {
  return currentUserVote.value?.response === response
})

async function handleVote(response: VoteResponse) {
  try {
    await submitVote(
      props.eventId,
      props.dateRange.id,
      response,
      comment.value || undefined
    )
    comment.value = ''
    showCommentInput.value = false
    emit('voteUpdated')
  } catch {
    // Error is handled by the composable
  }
}

function toggleCommentInput() {
  showCommentInput.value = !showCommentInput.value
}
</script>

<template>
  <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-4">
    <div class="flex items-start justify-between mb-3">
      <div>
        <h3 class="text-sm font-medium text-gray-900 dark:text-white">
          {{ formatDateDisplay(dateRange.start_date) }}
          <span v-if="dateRange.start_date !== dateRange.end_date">
            - {{ formatDateDisplay(dateRange.end_date) }}
          </span>
        </h3>
      </div>
    </div>

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

    <!-- Comment Input -->
    <div class="mb-4">
      <button
        type="button"
        class="text-sm text-indigo-600 dark:text-indigo-400 hover:underline"
        @click="toggleCommentInput"
      >
        {{ showCommentInput ? 'Hide comment' : 'Add a comment' }}
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
      </div>
    </div>

    <!-- Vote Summary -->
    <VoteSummaryBar :summary="dateRange.vote_summary" />

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
        {{ showVoters ? 'Hide' : 'Show' }} votes ({{ dateRange.vote_summary.total }})
      </button>
      <div
        v-if="showVoters"
        class="mt-3"
      >
        <VotersList :votes="dateRange.votes" />
      </div>
    </div>
  </div>
</template>
