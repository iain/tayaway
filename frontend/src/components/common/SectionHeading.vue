<script setup lang="ts">
import type { Component } from 'vue'

defineProps<{
  icon: Component
  title: string
}>()
</script>

<template>
  <div class="mb-4 flex items-center justify-between gap-4">
    <h2
      class="flex items-center gap-2 text-lg font-semibold text-gray-900 dark:text-white"
    >
      <component :is="icon" class="size-5 text-gray-400 dark:text-stone-500" />
      {{ title }}
    </h2>
    <slot />
  </div>
</template>
