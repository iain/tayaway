<script setup lang="ts">
// Visual heading for a band of related sections (Foundations, Atoms, …). The
// `id` anchors the band itself so the TOC can scroll to a group as well as to
// an individual section inside it.
defineProps<{
  id: string
  title: string
  description?: string
}>()
</script>

<template>
  <section :id="id" class="scroll-mt-6">
    <header class="mb-card">
      <h2 class="text-page-title-sm text-ink">{{ title }}</h2>
      <p v-if="description" class="text-ink-muted text-meta mt-1 max-w-prose">
        {{ description }}
      </p>
    </header>
    <div class="space-y-section">
      <slot />
    </div>
  </section>
</template>
