<script setup lang="ts">
defineEmits<{
  click: []
}>()
</script>

<template>
  <button
    type="button"
    class="inline-flex items-center gap-2 text-sm text-cyan-600 underline hover:text-cyan-700 dark:text-cyan-400 dark:hover:text-cyan-300"
    @click="$emit('click')"
  >
    <slot />
  </button>
</template>
