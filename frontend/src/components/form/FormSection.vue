<script setup lang="ts">
defineProps<{
  title: string
  description?: string
  border?: boolean
}>()
</script>

<template>
  <div :class="border ? 'border-b border-white/10 pb-12' : ''">
    <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">
      {{ title }}
    </h2>
    <p
      v-if="description"
      class="mt-1 text-sm/6 text-gray-600 dark:text-stone-400"
    >
      {{ description }}
    </p>
    <div class="mt-10 grid grid-cols-1 gap-x-6 gap-y-8 sm:grid-cols-6">
      <slot />
    </div>
  </div>
</template>
