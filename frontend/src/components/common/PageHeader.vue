<script setup lang="ts">
import type { Component } from 'vue'

// `icon` is the page-level expression of the amber-landmark signature — the
// same vocabulary as `SectionHeading`'s 20px icon, rendered one tier larger
// (28px) so the page anchor reads stronger than the regions inside it.
// Per the Amber-Icon Rule, this lives outside any card surface and announces
// the page as a region; it shouldn't appear on modal titles or card chrome.
defineProps<{
  title: string
  size?: 'sm' | 'default'
  dataTestid?: string
  icon?: Component
}>()
</script>

<template>
  <header class="mb-card flex items-start justify-between gap-4">
    <div class="min-w-0 flex-1 flex items-center gap-3">
      <component
        :is="icon"
        v-if="icon"
        class="shrink-0 text-amber-600 dark:text-amber-400"
        :class="size === 'sm' ? 'size-6' : 'size-7'"
        aria-hidden="true"
      />
      <div class="min-w-0 flex-1">
        <h1
          :data-testid="dataTestid"
          class="text-ink"
          :class="size === 'sm' ? 'text-page-title-sm' : 'text-page-title'"
        >
          {{ title }}
        </h1>
        <p v-if="$slots.subtitle" class="text-ink-muted text-meta mt-1">
          <slot name="subtitle" />
        </p>
      </div>
    </div>
    <slot />
  </header>
</template>
