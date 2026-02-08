<script setup lang="ts">
import { computed } from 'vue'
import { storeToRefs } from 'pinia'
import { useRoute, useRouter } from 'vue-router'
import {
  ArrowLeftIcon,
  PencilIcon,
  HandThumbUpIcon,
  UserIcon,
  CalendarIcon,
} from '@heroicons/vue/24/outline'
import { CheckCircleIcon } from '@heroicons/vue/24/solid'
import { useAuthStore, useWebSocketStore } from '@/stores'
import { useHydratedEvent } from '@/composables/useHydratedEvent'
import { useCalendar } from '@/composables/useCalendar'
import VoteSummaryBar from '@/components/votes/VoteSummaryBar.vue'

const route = useRoute()
const router = useRouter()
const authStore = useAuthStore()
const wsStore = useWebSocketStore()
const { user } = storeToRefs(authStore)
const { hasSynced } = storeToRefs(wsStore)
const { formatDateDisplay } = useCalendar()

const eventId = computed(() => route.params.id as string)

// Use hydrated event from pool for reactive updates
const { event } = useHydratedEvent(eventId)

const isOwner = computed(() => {
  return user.value?.id === event.value?.userId
})

// Sort date ranges by popularity (yes votes, then preferably_not, then total)
const rankedDateRanges = computed(() => {
  if (!event.value) return []
  return [...event.value.dateRanges].sort((a, b) => {
    // First by yes votes
    if (b.voteSummary.yes !== a.voteSummary.yes) {
      return b.voteSummary.yes - a.voteSummary.yes
    }
    // Then by preferably_not (fewer is better)
    if (a.voteSummary.preferably_not !== b.voteSummary.preferably_not) {
      return a.voteSummary.preferably_not - b.voteSummary.preferably_not
    }
    // Then by total participation
    return b.voteSummary.total - a.voteSummary.total
  })
})

// Get workspace members who haven't voted on ANY date range
const membersWhoHaventVoted = computed(() => {
  if (!event.value?.workspace) return []

  // Get all unique user IDs who have voted on at least one date range
  const voterUserIds = new Set<string>()
  for (const dateRange of event.value.dateRanges) {
    for (const vote of dateRange.votes) {
      voterUserIds.add(vote.userId)
    }
  }

  // Filter workspace members to those who haven't voted
  return event.value.workspace.members.filter(
    (member) => member.user && !voterUserIds.has(member.user.id)
  )
})

// Check if current user has voted on all date ranges
const currentUserVoteStatus = computed(() => {
  if (!event.value || !user.value) return { voted: 0, total: 0 }

  const total = event.value.dateRanges.length
  let voted = 0

  for (const dateRange of event.value.dateRanges) {
    if (dateRange.votes.some((v) => v.userId === user.value?.id)) {
      voted++
    }
  }

  return { voted, total }
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

      <!-- Vote CTA -->
      <section class="mb-8">
        <button
          type="button"
          class="inline-flex w-full items-center justify-center gap-2 rounded-lg bg-rose-600 px-6 py-4 text-lg font-semibold text-white shadow-sm hover:bg-rose-500 sm:w-auto"
          @click="handleVote"
        >
          <HandThumbUpIcon class="size-6" />
          Vote on Dates
        </button>
        <p
          v-if="currentUserVoteStatus.total > 0"
          class="mt-2 text-sm text-gray-500 dark:text-gray-400"
        >
          <template
            v-if="currentUserVoteStatus.voted === currentUserVoteStatus.total"
          >
            <CheckCircleIcon class="inline size-4 text-green-500" />
            You've voted on all {{ currentUserVoteStatus.total }} date options
          </template>
          <template v-else>
            You've voted on {{ currentUserVoteStatus.voted }} of
            {{ currentUserVoteStatus.total }} date options
          </template>
        </p>
      </section>

      <!-- Stats Grid -->
      <div class="grid gap-6 lg:grid-cols-2">
        <!-- Most Popular Dates -->
        <section class="rounded-lg bg-white p-6 shadow dark:bg-gray-800">
          <h2
            class="mb-4 flex items-center gap-2 text-lg font-semibold text-gray-900 dark:text-white"
          >
            <CalendarIcon class="size-5" />
            Date Rankings
          </h2>

          <div
            v-if="rankedDateRanges.length === 0"
            class="py-4 text-center text-gray-500 dark:text-gray-400"
          >
            No date ranges have been added yet.
          </div>

          <div v-else class="space-y-4">
            <div
              v-for="(dateRange, index) in rankedDateRanges"
              :key="dateRange.id"
              class="rounded-md border border-gray-200 p-4 dark:border-gray-700"
              :class="{
                'border-green-300 bg-green-50 dark:border-green-700 dark:bg-green-900/20':
                  index === 0 && dateRange.voteSummary.yes > 0,
              }"
            >
              <div class="mb-2 flex items-center justify-between">
                <span class="font-medium text-gray-900 dark:text-white">
                  <span
                    v-if="index === 0 && dateRange.voteSummary.yes > 0"
                    class="mr-2 text-green-600 dark:text-green-400"
                  >
                    #1
                  </span>
                  {{ formatDateDisplay(dateRange.startDate) }}
                  <span v-if="dateRange.startDate !== dateRange.endDate">
                    - {{ formatDateDisplay(dateRange.endDate) }}
                  </span>
                </span>
                <span class="text-sm text-gray-500 dark:text-gray-400">
                  {{ dateRange.voteSummary.total }}
                  {{ dateRange.voteSummary.total === 1 ? 'vote' : 'votes' }}
                </span>
              </div>
              <VoteSummaryBar :summary="dateRange.voteSummary" />
            </div>
          </div>
        </section>

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
              class="flex items-center gap-3 rounded-md bg-gray-50 px-3 py-2 dark:bg-gray-700/50"
            >
              <div
                class="flex size-8 items-center justify-center rounded-full bg-gray-200 dark:bg-gray-600"
              >
                <UserIcon class="size-4 text-gray-500 dark:text-gray-400" />
              </div>
              <span class="text-gray-900 dark:text-white">
                {{ member.user?.name || member.user?.email || 'Unknown' }}
              </span>
            </li>
          </ul>

          <p
            v-if="membersWhoHaventVoted.length > 0"
            class="mt-4 text-sm text-gray-500 dark:text-gray-400"
          >
            {{ membersWhoHaventVoted.length }}
            {{
              membersWhoHaventVoted.length === 1 ? 'person' : 'people'
            }}
            haven't voted yet
          </p>
        </section>
      </div>
    </div>
  </div>
</template>
