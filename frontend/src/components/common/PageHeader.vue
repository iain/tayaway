<script setup lang="ts">
defineProps<{
  title: string
  size?: 'sm' | 'default'
  dataTestid?: string
}>()
</script>

<template>
  <header class="mb-card flex items-start justify-between gap-4">
    <div class="min-w-0 flex-1">
      <h1
        :data-testid="dataTestid"
        class="text-ink"
        :class="size === 'sm' ? 'text-page-title-sm' : 'text-page-title'"
      >
        {{ title }}
      </h1>
      <p v-if="$slots.subtitle" class="text-ink-muted text-meta mt-1">
        <slot name="subtitle" />
      </p>
    </div>
    <slot />
  </header>
</template>
