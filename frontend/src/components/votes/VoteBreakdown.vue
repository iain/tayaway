<script setup lang="ts">
import { computed, ref, useId, type Component } from 'vue'
import { ChevronDownIcon } from '@heroicons/vue/24/outline'
import {
  CheckCircleIcon,
  EllipsisHorizontalCircleIcon,
  MinusCircleIcon,
  XCircleIcon,
} from '@heroicons/vue/24/solid'
import type {
  HydratedMember,
  HydratedVote,
} from '@/composables/useHydratedEvent'
import type { VoteResponse } from '@/types/pool'
import TextButton from '@/components/common/TextButton.vue'

const props = withDefaults(
  defineProps<{
    votes: HydratedVote[]
    // Omit where "who hasn't answered" isn't the question — the delete-confirm
    // modal is about the votes that are going away, not the roster.
    members?: HydratedMember[]
    // `inline` is for surfaces that already sit behind a disclosure of their
    // own; folding twice buries the comments for no gain.
    comments?: 'collapsed' | 'inline'
  }>(),
  { members: () => [], comments: 'collapsed' }
)

interface VoterGroup {
  key: string
  label: string
  icon: Component
  iconClass: string
  names: string[]
}

// Best answer first, so a row of names reads the same direction as the summary
// bar above it. Icon colours come from the state tokens rather than the raw
// ramp: green-500 and yellow-500 sit at ~1.8:1 on `surface` here, and worse on
// the #1 card's own green fill.
const RESPONSE_ORDER: (Omit<VoterGroup, 'key' | 'names'> & {
  response: VoteResponse
})[] = [
  {
    response: 'yes',
    label: 'Yes',
    icon: CheckCircleIcon,
    iconClass: 'text-state-success-ink',
  },
  {
    response: 'preferably_not',
    label: 'Preferably not',
    icon: MinusCircleIcon,
    iconClass: 'text-state-warning-ink',
  },
  {
    response: 'no',
    label: 'No',
    icon: XCircleIcon,
    iconClass: 'text-state-danger-ink',
  },
]

// A whole roster in one comma run buries the summary bar it is meant to
// support. Ten is past any normal friend group, so the fold only appears once
// the run has genuinely become a wall.
const NAME_RUN_LIMIT = 10

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
const commentEntries = computed(() =>
  props.votes.flatMap((vote) =>
    vote.comment
      ? [{ id: vote.id, name: memberName(vote.member), comment: vote.comment }]
      : []
  )
)

const uid = useId()
const commentsId = `${uid}-comments`
const namesId = (key: string): string => `${uid}-${key}`

const showComments = ref(false)
const expandedGroups = ref(new Set<string>())

function toggleGroup(key: string): void {
  if (expandedGroups.value.has(key)) {
    expandedGroups.value.delete(key)
  } else {
    expandedGroups.value.add(key)
  }
}

const groups = computed(() => {
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
  ]
    .filter((group) => group.names.length > 0)
    .map((group) => {
      const expanded = expandedGroups.value.has(group.key)
      return {
        ...group,
        expanded,
        overflow: group.names.length - NAME_RUN_LIMIT,
        shownNames: (expanded
          ? group.names
          : group.names.slice(0, NAME_RUN_LIMIT)
        ).join(', '),
      }
    })
})
</script>

<template>
  <div>
    <div v-if="groups.length === 0" class="text-ink-muted text-sm italic">
      No votes yet
    </div>
    <!-- From `sm` up the labels share one track, so every name run starts at the
         same x and the column scans. On phones that track would cost the "Yes"
         row ~65px of name width, so there the row just flows. -->
    <ul
      v-else
      class="grid gap-y-1 text-sm sm:grid-cols-[auto_auto_1fr] sm:gap-x-2"
    >
      <li
        v-for="group in groups"
        :key="group.key"
        data-testid="vote-breakdown-group"
        class="flex items-start gap-2 sm:col-span-3 sm:grid sm:grid-cols-subgrid"
      >
        <component
          :is="group.icon"
          class="mt-0.5 size-4 shrink-0"
          :class="group.iconClass"
          aria-hidden="true"
        />
        <span
          data-testid="vote-breakdown-label"
          class="text-ink-muted shrink-0"
        >
          {{ group.label }}
        </span>
        <span class="min-w-0 break-words">
          <span
            :id="namesId(group.key)"
            data-testid="vote-breakdown-names"
            class="text-ink"
          >
            {{ group.shownNames }}
          </span>
          <TextButton
            v-if="group.overflow > 0"
            data-testid="vote-breakdown-more"
            inline
            class="ml-1 align-baseline"
            :aria-expanded="group.expanded"
            :aria-controls="namesId(group.key)"
            @click="toggleGroup(group.key)"
          >
            {{ group.expanded ? 'Show fewer' : `+${group.overflow} more` }}
          </TextButton>
        </span>
      </li>
    </ul>

    <template v-if="commentEntries.length > 0">
      <TextButton
        v-if="comments === 'collapsed'"
        data-testid="vote-breakdown-comments-toggle"
        class="mt-2"
        :aria-expanded="showComments"
        :aria-controls="commentsId"
        @click="showComments = !showComments"
      >
        <ChevronDownIcon
          class="size-4 shrink-0 transition-transform"
          :class="showComments ? '' : '-rotate-90'"
          aria-hidden="true"
        />
        {{ commentEntries.length }}
        {{ commentEntries.length === 1 ? 'comment' : 'comments' }}
      </TextButton>

      <ul
        v-show="comments === 'inline' || showComments"
        :id="commentsId"
        data-testid="vote-breakdown-comments"
        class="mt-2 space-y-1"
      >
        <li
          v-for="entry in commentEntries"
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
