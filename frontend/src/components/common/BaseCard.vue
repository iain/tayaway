<script setup lang="ts">
defineProps<{
  padded?: boolean
  as?: string
}>()
</script>

<template>
  <component
    :is="as ?? 'div'"
    class="rounded-lg bg-white shadow dark:bg-stone-800"
    :class="{ 'p-6': padded }"
  >
    <slot />
  </component>
</template>
