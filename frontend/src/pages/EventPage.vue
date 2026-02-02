<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ArrowLeftIcon } from '@heroicons/vue/24/outline'
import type { Event } from '@/types'
import { useEvents } from '@/composables/useEvents'
import { useAuth } from '@/composables/useAuth'
import VotingCard from '@/components/votes/VotingCard.vue'

const route = useRoute()
const router = useRouter()
const { fetchEvent, loading, error } = useEvents()
const { user } = useAuth()

const event = ref<Event | null>(null)

onMounted(async () => {
  const id = route.params.id as string
  try {
    event.value = await fetchEvent(id)
  } catch {
    // Error handled by composable
  }
})

async function handleVoteUpdated(): Promise<void> {
  const id = route.params.id as string
  event.value = await fetchEvent(id)
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
            @vote-updated="handleVoteUpdated"
          />
        </div>
      </section>
    </div>
  </div>
</template>
