<script setup lang="ts">
import { computed } from 'vue'

const props = withDefaults(
  defineProps<{
    variant?: 'default' | 'danger'
    label: string
    hoverReveal?: boolean
    disabled?: boolean
  }>(),
  {
    variant: 'default',
  }
)

const classes = computed(() => [
  'cursor-pointer rounded p-1 transition-colors',
  props.variant === 'danger'
    ? 'text-gray-400 hover:text-red-500 dark:text-stone-500 dark:hover:text-red-400'
    : 'text-gray-400 hover:text-gray-600 dark:text-stone-500 dark:hover:text-stone-300',
  props.hoverReveal && 'sm:opacity-0 sm:group-hover:opacity-100',
  props.disabled && 'disabled:opacity-50',
])
</script>

<template>
  <button type="button" :class="classes" :disabled="disabled">
    <span class="sr-only">{{ label }}</span>
    <slot />
  </button>
</template>
