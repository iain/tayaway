<script setup lang="ts">
import type { Component } from 'vue'

defineProps<{
  icon: Component
  heading: string
  description: string
  iconClass?: string
}>()
</script>

<template>
  <div class="py-12 text-center">
    <component
      :is="icon"
      class="mx-auto size-12"
      :class="iconClass ?? 'text-amber-500 dark:text-amber-400'"
      aria-hidden="true"
    />
    <h3 class="text-ink mt-2 text-sm font-semibold">
      {{ heading }}
    </h3>
    <p class="text-ink-muted mt-1 text-base">
      {{ description }}
    </p>
    <div v-if="$slots.default" class="mt-6">
      <slot />
    </div>
  </div>
</template>
