<script setup lang="ts">
import type { Component } from 'vue'

defineProps<{
  icon: Component
  title: string
}>()
</script>

<template>
  <h2
    class="mb-4 flex items-center gap-2 text-lg font-semibold text-gray-900 dark:text-white"
  >
    <component :is="icon" class="size-5" />
    {{ title }}
  </h2>
</template>
