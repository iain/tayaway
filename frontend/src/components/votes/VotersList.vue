<script setup lang="ts">
import { computed } from 'vue'
import type { Vote } from '@/types'
import { CheckCircleIcon, XCircleIcon, MinusCircleIcon } from '@heroicons/vue/24/solid'

const props = defineProps<{
  votes: Vote[]
}>()

const sortedVotes = computed(() => {
  const order = { yes: 0, preferably_not: 1, no: 2 }
  return [...props.votes].sort((a, b) => order[a.response] - order[b.response])
})

function getResponseIcon(response: string) {
  switch (response) {
    case 'yes':
      return CheckCircleIcon
    case 'no':
      return XCircleIcon
    default:
      return MinusCircleIcon
  }
}

function getResponseColor(response: string) {
  switch (response) {
    case 'yes':
      return 'text-green-500'
    case 'no':
      return 'text-red-500'
    default:
      return 'text-yellow-500'
  }
}

function getResponseLabel(response: string) {
  switch (response) {
    case 'yes':
      return 'Yes'
    case 'no':
      return 'No'
    default:
      return 'Preferably not'
  }
}
</script>

<template>
  <div>
    <div
      v-if="votes.length === 0"
      class="text-sm text-gray-500 dark:text-gray-400 italic"
    >
      No votes yet
    </div>
    <ul
      v-else
      class="space-y-2"
    >
      <li
        v-for="vote in sortedVotes"
        :key="vote.id"
        class="flex items-start gap-2"
      >
        <component
          :is="getResponseIcon(vote.response)"
          class="size-5 shrink-0 mt-0.5"
          :class="getResponseColor(vote.response)"
        />
        <div class="min-w-0 flex-1">
          <div class="text-sm text-gray-900 dark:text-white">
            {{ vote.user?.name || vote.user?.email || 'Unknown user' }}
            <span class="text-gray-500 dark:text-gray-400">
              - {{ getResponseLabel(vote.response) }}
            </span>
          </div>
          <div
            v-if="vote.comment"
            class="text-xs text-gray-500 dark:text-gray-400 mt-0.5"
          >
            "{{ vote.comment }}"
          </div>
        </div>
      </li>
    </ul>
  </div>
</template>
