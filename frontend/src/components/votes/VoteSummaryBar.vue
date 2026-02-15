<script setup lang="ts">
import { computed } from 'vue'
import type { VoteSummary } from '@/composables/useHydratedEvent'

const props = defineProps<{
  summary: VoteSummary
}>()

const hasVotes = computed(() => props.summary.total > 0)

const percentages = computed(() => {
  if (!hasVotes.value) {
    return { yes: 0, no: 0, preferablyNot: 0 }
  }
  return {
    yes: (props.summary.yes / props.summary.total) * 100,
    no: (props.summary.no / props.summary.total) * 100,
    preferablyNot: (props.summary.preferably_not / props.summary.total) * 100,
  }
})
</script>

<template>
  <div>
    <div
      v-if="hasVotes"
      class="flex h-2 overflow-hidden rounded-full bg-gray-200 dark:bg-stone-700"
    >
      <div
        v-if="percentages.yes > 0"
        class="bg-green-500"
        :style="{ width: `${percentages.yes}%` }"
      />
      <div
        v-if="percentages.preferablyNot > 0"
        class="bg-yellow-500"
        :style="{ width: `${percentages.preferablyNot}%` }"
      />
      <div
        v-if="percentages.no > 0"
        class="bg-red-500"
        :style="{ width: `${percentages.no}%` }"
      />
    </div>
    <div v-else class="h-2 rounded-full bg-gray-200 dark:bg-stone-700" />
    <div class="mt-1 text-xs text-gray-500 dark:text-stone-400">
      <span v-if="hasVotes">
        {{ summary.yes }} yes, {{ summary.preferably_not }} preferably not,
        {{ summary.no }} no
      </span>
      <span v-else> No votes yet </span>
    </div>
  </div>
</template>
