<script setup lang="ts">
import { computed, ref, type Component } from 'vue'
import {
  ChevronDownIcon,
  ChevronUpIcon,
  EllipsisHorizontalCircleIcon,
} from '@heroicons/vue/24/outline'
import {
  CheckCircleIcon,
  MinusCircleIcon,
  XCircleIcon,
} from '@heroicons/vue/24/solid'
import type {
  HydratedMember,
  HydratedVote,
} from '@/composables/useHydratedEvent'
import type { VoteResponse } from '@/types/pool'
import TextButton from '@/components/common/TextButton.vue'

const props = defineProps<{
  votes: HydratedVote[]
  members: HydratedMember[]
}>()

interface VoterGroup {
  key: string
  label: string
  icon: Component
  iconClass: string
  names: string[]
}

// Best answer first, so a row of names reads the same direction as the summary
// bar above it.
const RESPONSE_ORDER: (Omit<VoterGroup, 'key' | 'names'> & {
  response: VoteResponse
})[] = [
  {
    response: 'yes',
    label: 'Yes',
    icon: CheckCircleIcon,
    iconClass: 'text-green-500',
  },
  {
    response: 'preferably_not',
    label: 'Preferably not',
    icon: MinusCircleIcon,
    iconClass: 'text-yellow-500',
  },
  { response: 'no', label: 'No', icon: XCircleIcon, iconClass: 'text-red-500' },
]

function memberName(member: HydratedMember | undefined): string {
  return member?.name || member?.email || 'Unknown member'
}

// Members with no vote on *this* option close the list, so a half-finished
// poll reads per date rather than only per poll.
const notVoted = computed<string[]>(() => {
  const voted = new Set(props.votes.map((vote) => vote.userId))
  return props.members
    .filter((member) => !voted.has(member.userId))
    .map(memberName)
})

// Names and answers live in the groups above, so the only thing left worth
// unfolding is what people actually wrote.
const comments = computed(() =>
  props.votes.flatMap((vote) =>
    vote.comment
      ? [{ id: vote.id, name: memberName(vote.member), comment: vote.comment }]
      : []
  )
)

const showComments = ref(false)

const groups = computed<VoterGroup[]>(() => {
  const responded: VoterGroup[] = RESPONSE_ORDER.map((group) => ({
    ...group,
    key: group.response,
    names: props.votes
      .filter((vote) => vote.response === group.response)
      .map((vote) => memberName(vote.member)),
  }))

  return [
    ...responded,
    {
      key: 'not_voted',
      label: 'Not voted',
      icon: EllipsisHorizontalCircleIcon,
      iconClass: 'text-ink-muted',
      names: notVoted.value,
    },
  ].filter((group) => group.names.length > 0)
})
</script>

<template>
  <!-- An option nobody has answered yet says nothing the summary bar's
       "No votes yet" doesn't already say. -->
  <div v-if="votes.length > 0">
    <ul class="space-y-1">
      <li
        v-for="group in groups"
        :key="group.key"
        data-testid="vote-breakdown-group"
        class="flex items-start gap-2 text-sm"
      >
        <component
          :is="group.icon"
          class="mt-0.5 size-4 shrink-0"
          :class="group.iconClass"
        />
        <span
          data-testid="vote-breakdown-label"
          class="text-ink-muted shrink-0"
        >
          {{ group.label }}
        </span>
        <span data-testid="vote-breakdown-names" class="text-ink min-w-0">
          {{ group.names.join(', ') }}
        </span>
      </li>
    </ul>

    <template v-if="comments.length > 0">
      <TextButton
        data-testid="vote-breakdown-comments-toggle"
        class="mt-2"
        @click="showComments = !showComments"
      >
        <component
          :is="showComments ? ChevronUpIcon : ChevronDownIcon"
          class="size-4"
        />
        {{ comments.length }}
        {{ comments.length === 1 ? 'comment' : 'comments' }}
      </TextButton>

      <ul v-if="showComments" class="mt-2 space-y-1">
        <li
          v-for="entry in comments"
          :key="entry.id"
          data-testid="vote-breakdown-comment"
          class="text-ink-muted text-sm"
        >
          <span class="text-ink">{{ entry.name }}</span>
          &mdash; &ldquo;{{ entry.comment }}&rdquo;
        </li>
      </ul>
    </template>
  </div>
</template>
