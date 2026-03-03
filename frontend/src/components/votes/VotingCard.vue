<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { ChevronDownIcon, ChevronUpIcon } from '@heroicons/vue/24/outline'
import type { VoteResponse } from '@/types/pool'
import type { HydratedDateRange } from '@/composables/useHydratedEvent'
import { useVotesStore } from '@/stores/votes'
import VoteSummaryBar from './VoteSummaryBar.vue'
import VotersList from './VotersList.vue'
import FormTextarea from '@/components/form/FormTextarea.vue'
import DateRangeDisplay from '@/components/common/DateRangeDisplay.vue'
import AppButton from '@/components/common/AppButton.vue'
import BaseCard from '@/components/common/BaseCard.vue'
import TextButton from '@/components/common/TextButton.vue'

const props = defineProps<{
  dateRange: HydratedDateRange
  eventId: string
  currentUserId: string | null
}>()

const votesStore = useVotesStore()

const loading = ref(false)
const showVoters = ref(false)
const comment = ref('')
const showCommentInput = ref(false)

const currentUserVote = computed(() => {
  if (!props.currentUserId) return null
  return (
    props.dateRange.votes.find((v) => v.userId === props.currentUserId) ?? null
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
  if (!props.currentUserId) return

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
  if (!currentUserVote.value || !props.currentUserId) return

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
  <BaseCard class="p-4">
    <div class="flex flex-col md:flex-row md:gap-6">
      <!-- Left side: Date range info and stats -->
      <div class="mb-4 flex-1 md:mb-0">
        <h3 class="mb-3 text-sm font-medium text-gray-900 dark:text-white">
          <DateRangeDisplay
            :start-date="dateRange.startDate"
            :end-date="dateRange.endDate"
          />
        </h3>

        <!-- Vote Summary -->
        <VoteSummaryBar :summary="dateRange.voteSummary" />

        <!-- Voters List Toggle -->
        <div class="mt-3 border-t border-gray-200 pt-3 dark:border-stone-700">
          <TextButton @click="showVoters = !showVoters">
            <component
              :is="showVoters ? ChevronUpIcon : ChevronDownIcon"
              class="size-4"
            />
            {{ showVoters ? 'Hide' : 'Show' }} votes ({{
              dateRange.voteSummary.total
            }})
          </TextButton>
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
            :aria-pressed="isSelected('yes') ? 'true' : 'false'"
            class="flex-1 rounded-md px-3 py-2 text-center text-sm font-medium whitespace-nowrap transition-colors"
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
            :aria-pressed="isSelected('preferably_not') ? 'true' : 'false'"
            class="flex-1 rounded-md px-3 py-2 text-center text-sm font-medium whitespace-nowrap transition-colors"
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
            :aria-pressed="isSelected('no') ? 'true' : 'false'"
            class="flex-1 rounded-md px-3 py-2 text-center text-sm font-medium whitespace-nowrap transition-colors"
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
          <TextButton @click="toggleCommentInput">
            {{
              showCommentInput
                ? 'Hide comment'
                : currentUserVote.comment
                  ? 'Edit comment'
                  : 'Add a comment'
            }}
          </TextButton>
          <div v-if="showCommentInput" class="mt-2">
            <FormTextarea
              :id="`comment-${dateRange.id}`"
              v-model="comment"
              label="Comment"
              placeholder="Optional comment..."
              :rows="2"
            />
            <AppButton
              :disabled="!hasCommentChanges"
              :loading="loading"
              loading-label="Saving..."
              class="mt-2"
              @click="handleCommentSubmit"
            >
              Save comment
            </AppButton>
          </div>
        </div>
      </div>
    </div>
  </BaseCard>
</template>
