<script setup lang="ts">
import { computed } from 'vue'
import { UserIcon } from '@heroicons/vue/24/outline'
import { CheckCircleIcon } from '@heroicons/vue/24/solid'
import type { HydratedEvent } from '@/composables/useHydratedEvent'

const props = defineProps<{
  event: HydratedEvent
  currentMemberId: string | null
}>()

interface MemberGroup {
  label: string
  members: { id: string; name: string | null; email: string }[]
}

const memberGroups = computed<MemberGroup[]>(() => {
  if (!props.event.workspace || !props.event.datePoll) return []

  const dateRanges = props.event.datePoll.dateRanges

  // Build set of all member IDs who voted at all
  const voterMemberIds = new Set<string>()
  const voteCountByMember = new Map<string, number>()
  for (const dateRange of dateRanges) {
    for (const vote of dateRange.votes) {
      voterMemberIds.add(vote.memberId)
      voteCountByMember.set(
        vote.memberId,
        (voteCountByMember.get(vote.memberId) || 0) + 1
      )
    }
  }

  const notVoted = props.event.workspace.members.filter(
    (member) => !voterMemberIds.has(member.id)
  )

  const partiallyVoted =
    dateRanges.length <= 1
      ? []
      : props.event.workspace.members.filter(
          (member) =>
            voteCountByMember.has(member.id) &&
            voteCountByMember.get(member.id)! < dateRanges.length
        )

  const groups: MemberGroup[] = []
  if (notVoted.length > 0) {
    groups.push({ label: 'Not voted yet', members: notVoted })
  }
  if (partiallyVoted.length > 0) {
    groups.push({ label: 'Incomplete votes', members: partiallyVoted })
  }
  return groups
})

const awaitingVotesCount = computed(() =>
  memberGroups.value.reduce((sum, group) => sum + group.members.length, 0)
)
</script>

<template>
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
      <div v-for="group in memberGroups" :key="group.label">
        <h3 class="mb-2 text-sm font-medium text-gray-500 dark:text-stone-400">
          {{ group.label }}
        </h3>
        <ul class="space-y-2">
          <li
            v-for="member in group.members"
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
        {{ awaitingVotesCount === 1 ? "person hasn't" : "people haven't" }}
        fully voted yet
      </p>
    </div>
  </section>
</template>
