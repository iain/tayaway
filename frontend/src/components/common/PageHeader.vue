<script setup lang="ts">
defineProps<{
  title: string
  size?: 'sm' | 'default'
  dataTestid?: string
}>()
</script>

<template>
  <header class="mb-6 flex items-center justify-between">
    <h1
      :data-testid="dataTestid"
      class="font-bold tracking-tight text-gray-900 dark:text-white"
      :class="size === 'sm' ? 'text-2xl' : 'text-3xl'"
    >
      {{ title }}
    </h1>
    <slot />
  </header>
</template>
