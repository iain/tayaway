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
        class="vote-bar bg-green-500"
        :style="{ flexBasis: `${percentages.yes}%` }"
      />
      <div
        v-if="percentages.preferablyNot > 0"
        class="vote-bar bg-yellow-500"
        :style="{ flexBasis: `${percentages.preferablyNot}%` }"
      />
      <div
        v-if="percentages.no > 0"
        class="vote-bar bg-red-500"
        :style="{ flexBasis: `${percentages.no}%` }"
      />
    </div>
    <div v-else class="h-2 rounded-full bg-gray-200 dark:bg-stone-700" />
    <div class="mt-1 text-xs text-ink-muted" data-testid="vote-summary">
      <span v-if="hasVotes">
        {{ summary.yes }} yes, {{ summary.preferably_not }} preferably not,
        {{ summary.no }} no
      </span>
      <span v-else> No votes yet </span>
    </div>
  </div>
</template>

<style scoped>
.vote-bar {
  transition: flex-basis 300ms cubic-bezier(0.25, 1, 0.5, 1);
}

@media (prefers-reduced-motion: reduce) {
  .vote-bar {
    transition-duration: 0.01ms;
  }
}
</style>
