<script setup lang="ts">
defineProps<{
  title: string
  description?: string
  border?: boolean
}>()
</script>

<template>
  <div :class="border ? 'border-line border-b pb-12' : ''">
    <h2 class="text-section-heading text-ink">
      {{ title }}
    </h2>
    <p v-if="description" class="text-meta text-ink-muted mt-1">
      {{ description }}
    </p>
    <div class="mt-10 grid grid-cols-1 gap-x-6 gap-y-8 sm:grid-cols-6">
      <slot />
    </div>
  </div>
</template>
