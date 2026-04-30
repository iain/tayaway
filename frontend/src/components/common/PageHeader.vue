<script setup lang="ts">
defineProps<{
  title: string
  size?: 'sm' | 'default'
  dataTestid?: string
}>()
</script>

<template>
  <header class="mb-6 flex items-start justify-between gap-4">
    <div class="min-w-0 flex-1">
      <h1
        :data-testid="dataTestid"
        class="font-bold tracking-tight text-gray-900 dark:text-white"
        :class="size === 'sm' ? 'text-2xl' : 'text-3xl'"
      >
        {{ title }}
      </h1>
      <p
        v-if="$slots.subtitle"
        class="mt-1 text-sm text-gray-500 dark:text-stone-400"
      >
        <slot name="subtitle" />
      </p>
    </div>
    <slot />
  </header>
</template>
