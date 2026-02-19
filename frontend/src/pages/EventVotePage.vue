<script setup lang="ts">
import { computed } from 'vue'
import { storeToRefs } from 'pinia'
import { useRoute, useRouter } from 'vue-router'
import { ArrowLeftIcon } from '@heroicons/vue/24/outline'
import { useAuthStore } from '@/stores'
import { useHydratedEvent } from '@/composables/useHydratedEvent'
import { isPollOpen } from '@/utils/poll'
import VotingCard from '@/components/votes/VotingCard.vue'
import TextButton from '@/components/common/TextButton.vue'

const route = useRoute()
const router = useRouter()
const authStore = useAuthStore()
const { currentMemberId } = storeToRefs(authStore)

const eventId = computed(() => route.params.id as string)

// Use hydrated event from pool for reactive updates
const { event } = useHydratedEvent(eventId)

const pollOpen = computed(() => isPollOpen(event.value?.datePoll))

const dateRanges = computed(() => {
  return event.value?.datePoll?.dateRanges ?? []
})

function handleBack(): void {
  router.push(`/events/${eventId.value}`)
}
</script>

<template>
  <div>
    <div class="mb-6">
      <TextButton @click="handleBack">
        <ArrowLeftIcon class="size-4" />
        Back to Event
      </TextButton>
    </div>

    <div v-if="!event" class="text-gray-500 dark:text-stone-400">
      Event not found
    </div>

    <div
      v-else-if="!event.datePoll || !pollOpen"
      class="py-8 text-center text-gray-500 dark:text-stone-400"
    >
      <p class="mb-2 text-lg font-medium">Voting is closed</p>
      <p>The date poll is no longer accepting votes.</p>
      <TextButton class="mt-4" @click="handleBack">
        <ArrowLeftIcon class="size-4" />
        Back to Event
      </TextButton>
    </div>

    <div v-else>
      <!-- Event Header -->
      <header class="mb-8">
        <h1
          class="text-3xl font-bold tracking-tight text-gray-900 dark:text-white"
        >
          {{ event.name }}
        </h1>
        <p class="mt-2 text-sm text-gray-500 dark:text-stone-400">
          Vote on your preferred dates below
        </p>
      </header>

      <!-- Date Ranges with Voting -->
      <section>
        <h2 class="mb-4 text-lg font-semibold text-gray-900 dark:text-white">
          Date Options
        </h2>

        <div v-if="dateRanges.length === 0" class="py-8 text-center">
          <p class="text-gray-500 dark:text-stone-400">
            No date ranges have been added yet.
          </p>
        </div>

        <div v-else class="space-y-4">
          <VotingCard
            v-for="dateRange in dateRanges"
            :key="dateRange.id"
            :date-range="dateRange"
            :event-id="event.id"
            :current-member-id="currentMemberId"
          />
        </div>
      </section>
    </div>
  </div>
</template>
