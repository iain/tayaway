<script setup lang="ts">
import { computed } from 'vue'

const props = withDefaults(
  defineProps<{
    variant?: 'primary' | 'secondary'
    disabled?: boolean
  }>(),
  { variant: 'primary' }
)

defineEmits<{
  click: []
}>()

const variantClass = computed(() =>
  props.variant === 'secondary'
    ? 'text-gray-500 hover:text-gray-700 dark:text-stone-400 dark:hover:text-stone-300'
    : 'text-cyan-600 underline hover:text-cyan-700 dark:text-cyan-400 dark:hover:text-cyan-300'
)
</script>

<template>
  <button
    type="button"
    class="inline-flex cursor-pointer items-center gap-2 text-sm disabled:cursor-not-allowed disabled:opacity-50"
    :class="variantClass"
    :disabled="disabled"
    @click="$emit('click')"
  >
    <slot />
  </button>
</template>
