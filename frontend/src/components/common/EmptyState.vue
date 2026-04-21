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
    <h3 class="mt-2 text-sm font-semibold text-gray-900 dark:text-white">
      {{ heading }}
    </h3>
    <p class="mt-1 text-base text-gray-500 dark:text-stone-400">
      {{ description }}
    </p>
    <div v-if="$slots.default" class="mt-6">
      <slot />
    </div>
  </div>
</template>
