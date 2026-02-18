<script setup lang="ts">
defineProps<{
  title: string
  dataTestid?: string
}>()
</script>

<template>
  <header class="mb-6 flex items-center justify-between">
    <h1
      :data-testid="dataTestid"
      class="text-3xl font-bold tracking-tight text-gray-900 dark:text-white"
    >
      {{ title }}
    </h1>
    <slot />
  </header>
</template>
