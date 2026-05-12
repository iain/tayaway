<script setup lang="ts">
import type { Component } from 'vue'

defineProps<{
  icon: Component
  title: string
}>()
</script>

<template>
  <div class="mb-heading flex items-center justify-between gap-4">
    <h2 class="text-section-heading text-ink flex items-center gap-2">
      <component :is="icon" class="size-5 text-amber-600 dark:text-amber-400" />
      {{ title }}
    </h2>
    <slot />
  </div>
</template>
