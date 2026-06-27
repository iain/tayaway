<script setup lang="ts">
import { computed, type Component } from 'vue'

// `headingLevel` keeps the visual heading (text-sm, semibold) but lets a page
// place the empty state correctly in its document outline: an empty state that
// sits under a page's <h1> should announce as <h2>, not skip to <h3>. Default
// stays 3 so existing standalone usages render unchanged.
const props = withDefaults(
  defineProps<{
    icon: Component
    heading: string
    description: string
    iconClass?: string
    headingLevel?: 2 | 3
  }>(),
  { headingLevel: 3 }
)

const headingTag = computed(() => `h${props.headingLevel}`)
</script>

<template>
  <div class="py-12 text-center">
    <component
      :is="icon"
      class="mx-auto size-12"
      :class="iconClass ?? 'text-amber-500 dark:text-amber-400'"
      aria-hidden="true"
    />
    <component :is="headingTag" class="text-ink mt-2 text-sm font-semibold">
      {{ heading }}
    </component>
    <p class="text-ink-muted mt-1 text-base">
      {{ description }}
    </p>
    <div v-if="$slots.default" class="mt-6">
      <slot />
    </div>
  </div>
</template>
