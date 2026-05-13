<script setup lang="ts">
// The "Composition" strip that sits at the bottom of an atom's section card.
// Surfaces a named rule from DESIGN.md alongside a live demo of the rule in
// practice — the gallery's job is not just to show variants but to make the
// rules that govern them visible at the point of consumption.
defineProps<{
  rule: string
  statement: string
  doc?: string
}>()
</script>

<template>
  <div class="border-line mt-6 border-t pt-6">
    <div class="mb-3 flex flex-wrap items-baseline gap-x-2">
      <span class="text-label text-ink font-semibold">{{ rule }}.</span>
      <span class="text-ink-muted text-meta">{{ statement }}</span>
      <a
        v-if="doc"
        :href="doc"
        target="_blank"
        rel="noopener"
        class="focus-visible:outline-focus text-meta text-cyan-600 underline hover:text-cyan-700 focus-visible:outline-2 focus-visible:outline-offset-2 dark:text-cyan-400 dark:hover:text-cyan-300"
        >See DESIGN.md →</a
      >
    </div>
    <div>
      <slot />
    </div>
  </div>
</template>
