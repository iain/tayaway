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

<!-- The segments deliberately stay on the bright 500 ramp while VoteBreakdown's
     glyphs use the deeper `state-*-ink` tokens. They are different jobs: a 16px
     glyph needs weight to read against `surface`, an 8px band does not. Swapping
     the band to the ink tier does not help either — it only moves the
     indistinguishable pair from green|yellow (1.05:1) to yellow|red (1.05:1),
     and darkens the bar for nothing. Segment order is fixed and the counts are
     spelled out below, so WCAG 1.4.11 is satisfied by the text, not the hues. -->
<template>
  <div>
    <div v-if="hasVotes" class="bg-line flex h-2 overflow-hidden rounded-full">
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
    <div v-else class="bg-line h-2 rounded-full" />
    <div class="text-ink-muted mt-1 text-xs" data-testid="vote-summary">
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
