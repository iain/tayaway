<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { storeToRefs } from 'pinia'
import { useRoute, useRouter } from 'vue-router'
import { ArrowLeftIcon } from '@heroicons/vue/24/outline'
import type { Event, Vote, VoteSummary } from '@/types'
import { useEventsStore, useAuthStore } from '@/stores'
import VotingCard from '@/components/votes/VotingCard.vue'

const route = useRoute()
const router = useRouter()
const eventsStore = useEventsStore()
const authStore = useAuthStore()
const { loading, error } = storeToRefs(eventsStore)
const { user } = storeToRefs(authStore)

const event = ref<Event | null>(null)

onMounted(async () => {
  const id = route.params.id as string
  try {
    event.value = await eventsStore.fetchEvent(id)
  } catch {
    // Error handled by store
  }
})

function handleVoteUpdated(vote: Vote, dateRangeId: string): void {
  if (!event.value) return

  const dateRange = event.value.date_ranges.find(dr => dr.id === dateRangeId)
  if (!dateRange) return

  // Find existing vote by this user or add new one
  const existingIndex = dateRange.votes.findIndex(v => v.user_id === vote.user_id)
  if (existingIndex >= 0) {
    dateRange.votes[existingIndex] = vote
  } else {
    dateRange.votes.push(vote)
  }

  // Recalculate vote summary
  dateRange.vote_summary = calculateVoteSummary(dateRange.votes)
}

function calculateVoteSummary(votes: Vote[]): VoteSummary {
  return {
    yes: votes.filter(v => v.response === 'yes').length,
    no: votes.filter(v => v.response === 'no').length,
    preferably_not: votes.filter(v => v.response === 'preferably_not').length,
    total: votes.length,
  }
}

function handleBack(): void {
  router.push('/events')
}
</script>

<template>
  <div>
    <div class="mb-6">
      <button
        type="button"
        class="inline-flex items-center gap-2 text-sm text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white"
        @click="handleBack"
      >
        <ArrowLeftIcon class="size-4" />
        Back to Events
      </button>
    </div>

    <div
      v-if="loading"
      class="text-gray-500 dark:text-gray-400"
    >
      Loading event...
    </div>

    <div
      v-else-if="error"
      class="text-red-600 dark:text-red-400"
    >
      {{ error }}
    </div>

    <div
      v-else-if="!event"
      class="text-gray-500 dark:text-gray-400"
    >
      Event not found
    </div>

    <div v-else>
      <!-- Event Header -->
      <header class="mb-8">
        <h1
          data-testid="event-name"
          class="text-3xl font-bold tracking-tight text-gray-900 dark:text-white"
        >
          {{ event.name }}
        </h1>
        <p
          v-if="event.description"
          class="mt-2 text-lg text-gray-600 dark:text-gray-400"
        >
          {{ event.description }}
        </p>
        <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          Created by {{ event.user?.name || event.user?.email || 'Unknown' }}
        </p>
      </header>

      <!-- Date Ranges with Voting -->
      <section>
        <h2 class="text-lg font-semibold text-gray-900 dark:text-white mb-4">
          Vote on Date Options
        </h2>

        <div
          v-if="event.date_ranges.length === 0"
          class="text-gray-500 dark:text-gray-400 italic"
        >
          No date ranges have been added to this event yet.
        </div>

        <div
          v-else
          class="space-y-4"
        >
          <VotingCard
            v-for="dateRange in event.date_ranges"
            :key="dateRange.id"
            :date-range="dateRange"
            :event-id="event.id"
            :current-user="user"
            @vote-updated="(vote, drId) => handleVoteUpdated(vote, drId)"
          />
        </div>
      </section>
    </div>
  </div>
</template>
