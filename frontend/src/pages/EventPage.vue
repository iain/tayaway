<script setup lang="ts">
import { computed } from 'vue'
import { storeToRefs } from 'pinia'
import { useRoute, useRouter } from 'vue-router'
import { ArrowLeftIcon, PencilIcon, UserIcon } from '@heroicons/vue/24/outline'
import { CheckCircleIcon } from '@heroicons/vue/24/solid'
import { useAuthStore, useWebSocketStore } from '@/stores'
import { useHydratedEvent } from '@/composables/useHydratedEvent'
import DatePollSection from '@/components/events/DatePollSection.vue'

const route = useRoute()
const router = useRouter()
const authStore = useAuthStore()
const wsStore = useWebSocketStore()
const { user } = storeToRefs(authStore)
const { hasSynced } = storeToRefs(wsStore)

const eventId = computed(() => route.params.id as string)

// Use hydrated event from pool for reactive updates
const { event } = useHydratedEvent(eventId)

const isOwner = computed(() => {
  return user.value?.id === event.value?.userId
})

// Get workspace members who haven't voted on ANY date range
const membersWhoHaventVoted = computed(() => {
  if (!event.value?.workspace || !event.value.datePoll) return []

  // Get all unique user IDs who have voted on at least one date range
  const voterUserIds = new Set<string>()
  for (const dateRange of event.value.datePoll.dateRanges) {
    for (const vote of dateRange.votes) {
      voterUserIds.add(vote.userId)
    }
  }

  // Filter workspace members to those who haven't voted
  return event.value.workspace.members.filter(
    (member) => member.user && !voterUserIds.has(member.user.id)
  )
})

function handleBack(): void {
  router.push('/events')
}

function handleEdit(): void {
  router.push(`/events/${eventId.value}/edit`)
}

function handleVote(): void {
  router.push(`/events/${eventId.value}/vote`)
}
</script>

<template>
  <div>
    <div class="mb-6 flex items-center justify-between">
      <button
        type="button"
        class="inline-flex items-center gap-2 text-sm text-gray-600 hover:text-gray-900 dark:text-gray-400 dark:hover:text-white"
        @click="handleBack"
      >
        <ArrowLeftIcon class="size-4" />
        Back to Events
      </button>
      <button
        v-if="isOwner"
        type="button"
        class="inline-flex items-center gap-2 text-sm text-gray-600 hover:text-gray-900 dark:text-gray-400 dark:hover:text-white"
        @click="handleEdit"
      >
        <PencilIcon class="size-4" />
        Edit Event
      </button>
    </div>

    <div v-if="!hasSynced" class="text-gray-500 dark:text-gray-400">
      Loading...
    </div>

    <div v-else-if="!event" class="text-gray-500 dark:text-gray-400">
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

      <!-- Stats Grid -->
      <div class="grid gap-6 lg:grid-cols-2">
        <!-- Date Poll Section -->
        <DatePollSection
          :event="event"
          :is-owner="isOwner"
          :current-user-id="user?.id"
          @vote="handleVote"
        />

        <!-- Who Hasn't Voted -->
        <section class="rounded-lg bg-white p-6 shadow dark:bg-gray-800">
          <h2
            class="mb-4 flex items-center gap-2 text-lg font-semibold text-gray-900 dark:text-white"
          >
            <UserIcon class="size-5" />
            Awaiting Votes
          </h2>

          <div
            v-if="!event.workspace"
            class="py-4 text-center text-gray-500 dark:text-gray-400"
          >
            Loading workspace members...
          </div>

          <div
            v-else-if="!event.datePoll"
            class="py-4 text-center text-gray-500 dark:text-gray-400"
          >
            Open a date poll to start collecting votes.
          </div>

          <div
            v-else-if="membersWhoHaventVoted.length === 0"
            class="py-4 text-center"
          >
            <CheckCircleIcon class="mx-auto mb-2 size-8 text-green-500" />
            <p class="text-gray-600 dark:text-gray-400">Everyone has voted!</p>
          </div>

          <ul v-else class="space-y-2">
            <li
              v-for="member in membersWhoHaventVoted"
              :key="member.id"
              class="flex items-center gap-3 rounded-md px-3 py-2"
              :class="
                member.user?.id === user?.id
                  ? 'bg-amber-50 ring-1 ring-amber-200 dark:bg-amber-900/20 dark:ring-amber-800'
                  : 'bg-gray-50 dark:bg-gray-700/50'
              "
            >
              <div
                class="flex size-8 items-center justify-center rounded-full"
                :class="
                  member.user?.id === user?.id
                    ? 'bg-amber-200 dark:bg-amber-800'
                    : 'bg-gray-200 dark:bg-gray-600'
                "
              >
                <UserIcon
                  class="size-4"
                  :class="
                    member.user?.id === user?.id
                      ? 'text-amber-600 dark:text-amber-400'
                      : 'text-gray-500 dark:text-gray-400'
                  "
                />
              </div>
              <span class="text-gray-900 dark:text-white">
                {{ member.user?.name || member.user?.email || 'Unknown' }}
                <span
                  v-if="member.user?.id === user?.id"
                  class="text-sm text-amber-600 dark:text-amber-400"
                >
                  (you)
                </span>
              </span>
            </li>
          </ul>

          <p
            v-if="membersWhoHaventVoted.length > 0"
            class="mt-4 text-sm text-gray-500 dark:text-gray-400"
          >
            {{ membersWhoHaventVoted.length }}
            {{ membersWhoHaventVoted.length === 1 ? 'person' : 'people' }}
            haven't voted yet
          </p>
        </section>
      </div>
    </div>
  </div>
</template>
