<script setup lang="ts">
import { computed, type Component } from 'vue'

// `headingLevel` keeps the visual heading but lets a caller place it correctly
// in the document outline: a heading nested under a page's own <h2> should
// announce as <h3>. Default stays 2 so existing usages render unchanged.
const props = withDefaults(
  defineProps<{
    icon: Component
    title: string
    subtitle?: string
    headingLevel?: 2 | 3
  }>(),
  { headingLevel: 2, subtitle: undefined }
)

const headingTag = computed(() => `h${props.headingLevel}`)
</script>

<template>
  <div class="mb-heading flex items-center justify-between gap-4">
    <div class="flex min-w-0 items-center gap-2">
      <component
        :is="icon"
        class="size-5 shrink-0 text-amber-600 dark:text-amber-400"
      />
      <div class="min-w-0">
        <component :is="headingTag" class="text-section-heading text-ink">
          {{ title }}
        </component>
        <p v-if="subtitle" class="text-ink-muted text-meta">{{ subtitle }}</p>
      </div>
    </div>
    <slot />
  </div>
</template>
