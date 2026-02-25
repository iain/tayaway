<script setup lang="ts">
import { computed } from 'vue'
import { UserIcon } from '@heroicons/vue/24/outline'
import { CheckCircleIcon } from '@heroicons/vue/24/solid'
import type { HydratedEvent } from '@/composables/useHydratedEvent'

const props = defineProps<{
  event: HydratedEvent
  currentUserId: string | null
}>()

interface MemberGroup {
  label: string
  completed: boolean
  members: { id: string; userId: string; name: string | null; email: string }[]
}

const memberGroups = computed<MemberGroup[]>(() => {
  if (!props.event.workspace || !props.event.datePoll) return []

  const dateRanges = props.event.datePoll.dateRanges
  const members = props.event.workspace.members

  const voteCountByMember = new Map<string, number>()
  for (const dateRange of dateRanges) {
    for (const vote of dateRange.votes) {
      voteCountByMember.set(
        vote.userId,
        (voteCountByMember.get(vote.userId) || 0) + 1
      )
    }
  }

  const fullyVoted = members.filter(
    (m) => voteCountByMember.get(m.userId) === dateRanges.length
  )
  const partiallyVoted =
    dateRanges.length <= 1
      ? []
      : members.filter(
          (m) =>
            voteCountByMember.has(m.userId) &&
            voteCountByMember.get(m.userId)! < dateRanges.length
        )
  const notVoted = members.filter((m) => !voteCountByMember.has(m.userId))

  const groups: MemberGroup[] = []
  if (notVoted.length > 0) {
    groups.push({ label: 'Not voted yet', completed: false, members: notVoted })
  }
  if (partiallyVoted.length > 0) {
    groups.push({
      label: 'Incomplete votes',
      completed: false,
      members: partiallyVoted,
    })
  }
  if (fullyVoted.length > 0) {
    groups.push({ label: 'Voted', completed: true, members: fullyVoted })
  }
  return groups
})

const awaitingVotesCount = computed(() =>
  memberGroups.value
    .filter((g) => !g.completed)
    .reduce((sum, g) => sum + g.members.length, 0)
)
</script>

<template>
  <section
    data-testid="awaiting-votes-section"
    class="rounded-lg bg-white p-6 shadow dark:bg-stone-800"
  >
    <h2
      class="mb-4 flex items-center gap-2 text-lg font-semibold text-gray-900 dark:text-white"
    >
      <UserIcon class="size-5" />
      Votes
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
      <div v-for="group in memberGroups" :key="group.label">
        <h3
          class="mb-2 text-sm font-medium"
          :class="
            group.completed
              ? 'text-green-600 dark:text-green-400'
              : 'text-gray-500 dark:text-stone-400'
          "
        >
          {{ group.label }}
        </h3>
        <ul class="space-y-2">
          <li
            v-for="member in group.members"
            :key="member.id"
            class="flex items-center gap-3 rounded-md px-3 py-2"
            :class="
              group.completed
                ? 'bg-green-50 dark:bg-green-900/20'
                : member.userId === currentUserId
                  ? 'bg-amber-50 ring-1 ring-amber-200 dark:bg-amber-900/20 dark:ring-amber-800'
                  : 'bg-gray-50 dark:bg-stone-700/50'
            "
          >
            <div
              class="flex size-8 items-center justify-center rounded-full"
              :class="
                group.completed
                  ? 'bg-green-200 dark:bg-green-800'
                  : member.userId === currentUserId
                    ? 'bg-amber-200 dark:bg-amber-800'
                    : 'bg-gray-200 dark:bg-stone-600'
              "
            >
              <CheckCircleIcon
                v-if="group.completed"
                class="size-4 text-green-600 dark:text-green-400"
              />
              <UserIcon
                v-else
                class="size-4"
                :class="
                  member.userId === currentUserId
                    ? 'text-amber-600 dark:text-amber-400'
                    : 'text-gray-500 dark:text-stone-400'
                "
              />
            </div>
            <span class="text-gray-900 dark:text-white">
              {{ member.name || member.email || 'Unknown' }}
              <span
                v-if="member.userId === currentUserId"
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
        {{ awaitingVotesCount === 1 ? "person hasn't" : "people haven't" }}
        fully voted yet
      </p>
    </div>
  </section>
</template>
