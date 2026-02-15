<script setup lang="ts">
import { computed } from 'vue'
import { storeToRefs } from 'pinia'
import { useRoute, useRouter } from 'vue-router'
import { ArrowLeftIcon, PencilIcon, UserIcon } from '@heroicons/vue/24/outline'
import { CheckCircleIcon } from '@heroicons/vue/24/solid'
import { useAuthStore } from '@/stores'
import { useHydratedEvent } from '@/composables/useHydratedEvent'
import DatePollSection from '@/components/events/DatePollSection.vue'

const route = useRoute()
const router = useRouter()
const authStore = useAuthStore()
const { currentMemberId } = storeToRefs(authStore)

const eventId = computed(() => route.params.id as string)

// Use hydrated event from pool for reactive updates
const { event } = useHydratedEvent(eventId)

const isOwner = computed(() => {
  return currentMemberId.value === event.value?.memberId
})

// Categorize workspace members by voting completeness
const membersNotVoted = computed(() => {
  if (!event.value?.workspace || !event.value.datePoll) return []

  const dateRanges = event.value.datePoll.dateRanges
  const voterMemberIds = new Set<string>()
  for (const dateRange of dateRanges) {
    for (const vote of dateRange.votes) {
      voterMemberIds.add(vote.memberId)
    }
  }

  return event.value.workspace.members.filter(
    (member) => !voterMemberIds.has(member.id)
  )
})

const membersPartiallyVoted = computed(() => {
  if (!event.value?.workspace || !event.value.datePoll) return []

  const dateRanges = event.value.datePoll.dateRanges
  if (dateRanges.length <= 1) return []

  // Count how many date ranges each member has voted on
  const voteCountByMember = new Map<string, number>()
  for (const dateRange of dateRanges) {
    for (const vote of dateRange.votes) {
      voteCountByMember.set(
        vote.memberId,
        (voteCountByMember.get(vote.memberId) || 0) + 1
      )
    }
  }

  return event.value.workspace.members.filter(
    (member) =>
      voteCountByMember.has(member.id) &&
      voteCountByMember.get(member.id)! < dateRanges.length
  )
})

const awaitingVotesCount = computed(
  () => membersNotVoted.value.length + membersPartiallyVoted.value.length
)

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
        class="inline-flex items-center gap-2 text-sm text-cyan-600 underline hover:text-cyan-700 dark:text-cyan-400 dark:hover:text-cyan-300"
        @click="handleBack"
      >
        <ArrowLeftIcon class="size-4" />
        Back to Events
      </button>
      <button
        v-if="isOwner"
        type="button"
        class="inline-flex items-center gap-2 text-sm text-cyan-600 underline hover:text-cyan-700 dark:text-cyan-400 dark:hover:text-cyan-300"
        @click="handleEdit"
      >
        <PencilIcon class="size-4" />
        Edit Event
      </button>
    </div>

    <div v-if="!event" class="text-gray-500 dark:text-stone-400">
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
          class="mt-2 text-lg text-gray-600 dark:text-stone-400"
        >
          {{ event.description }}
        </p>
        <p class="mt-2 text-sm text-gray-500 dark:text-stone-400">
          Created by
          {{ event.member?.name || event.member?.email || 'Unknown' }}
        </p>
      </header>

      <!-- Stats Grid -->
      <div class="grid gap-6 lg:grid-cols-2">
        <!-- Date Poll Section -->
        <DatePollSection
          :event="event"
          :is-owner="isOwner"
          :current-member-id="currentMemberId"
          @vote="handleVote"
        />

        <!-- Who Hasn't Voted -->
        <section class="rounded-lg bg-white p-6 shadow dark:bg-stone-800">
          <h2
            class="mb-4 flex items-center gap-2 text-lg font-semibold text-gray-900 dark:text-white"
          >
            <UserIcon class="size-5" />
            Awaiting Votes
          </h2>

          <div
            v-if="!event.workspace"
            class="py-4 text-center text-gray-500 dark:text-stone-400"
          >
            Loading workspace members...
          </div>

          <div
            v-else-if="!event.datePoll"
            class="py-4 text-center text-gray-500 dark:text-stone-400"
          >
            Open a date poll to start collecting votes.
          </div>

          <div v-else-if="awaitingVotesCount === 0" class="py-4 text-center">
            <CheckCircleIcon class="mx-auto mb-2 size-8 text-green-500" />
            <p class="text-gray-600 dark:text-stone-400">Everyone has voted!</p>
          </div>

          <div v-else class="space-y-4">
            <!-- Not voted at all -->
            <div v-if="membersNotVoted.length > 0">
              <h3
                class="mb-2 text-sm font-medium text-gray-500 dark:text-stone-400"
              >
                Not voted yet
              </h3>
              <ul class="space-y-2">
                <li
                  v-for="member in membersNotVoted"
                  :key="member.id"
                  class="flex items-center gap-3 rounded-md px-3 py-2"
                  :class="
                    member.id === currentMemberId
                      ? 'bg-amber-50 ring-1 ring-amber-200 dark:bg-amber-900/20 dark:ring-amber-800'
                      : 'bg-gray-50 dark:bg-stone-700/50'
                  "
                >
                  <div
                    class="flex size-8 items-center justify-center rounded-full"
                    :class="
                      member.id === currentMemberId
                        ? 'bg-amber-200 dark:bg-amber-800'
                        : 'bg-gray-200 dark:bg-stone-600'
                    "
                  >
                    <UserIcon
                      class="size-4"
                      :class="
                        member.id === currentMemberId
                          ? 'text-amber-600 dark:text-amber-400'
                          : 'text-gray-500 dark:text-stone-400'
                      "
                    />
                  </div>
                  <span class="text-gray-900 dark:text-white">
                    {{ member.name || member.email || 'Unknown' }}
                    <span
                      v-if="member.id === currentMemberId"
                      class="text-sm text-amber-600 dark:text-amber-400"
                    >
                      (you)
                    </span>
                  </span>
                </li>
              </ul>
            </div>

            <!-- Voted on some but not all date ranges -->
            <div v-if="membersPartiallyVoted.length > 0">
              <h3
                class="mb-2 text-sm font-medium text-gray-500 dark:text-stone-400"
              >
                Incomplete votes
              </h3>
              <ul class="space-y-2">
                <li
                  v-for="member in membersPartiallyVoted"
                  :key="member.id"
                  class="flex items-center gap-3 rounded-md px-3 py-2"
                  :class="
                    member.id === currentMemberId
                      ? 'bg-amber-50 ring-1 ring-amber-200 dark:bg-amber-900/20 dark:ring-amber-800'
                      : 'bg-gray-50 dark:bg-stone-700/50'
                  "
                >
                  <div
                    class="flex size-8 items-center justify-center rounded-full"
                    :class="
                      member.id === currentMemberId
                        ? 'bg-amber-200 dark:bg-amber-800'
                        : 'bg-gray-200 dark:bg-stone-600'
                    "
                  >
                    <UserIcon
                      class="size-4"
                      :class="
                        member.id === currentMemberId
                          ? 'text-amber-600 dark:text-amber-400'
                          : 'text-gray-500 dark:text-stone-400'
                      "
                    />
                  </div>
                  <span class="text-gray-900 dark:text-white">
                    {{ member.name || member.email || 'Unknown' }}
                    <span
                      v-if="member.id === currentMemberId"
                      class="text-sm text-amber-600 dark:text-amber-400"
                    >
                      (you)
                    </span>
                  </span>
                </li>
              </ul>
            </div>

            <p class="text-sm text-gray-500 dark:text-stone-400">
              {{ awaitingVotesCount }}
              {{
                awaitingVotesCount === 1 ? "person hasn't" : "people haven't"
              }}
              fully voted yet
            </p>
          </div>
        </section>
      </div>
    </div>
  </div>
</template>
