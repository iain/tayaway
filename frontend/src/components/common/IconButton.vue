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
  'cursor-pointer rounded p-2 transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-rose-500 min-h-[44px] min-w-[44px] inline-flex items-center justify-center sm:min-h-0 sm:min-w-0 sm:p-1',
  props.variant === 'danger'
    ? 'text-gray-400 hover:text-red-500 dark:text-stone-500 dark:hover:text-red-400'
    : 'text-gray-400 hover:text-gray-600 dark:text-stone-500 dark:hover:text-stone-300',
  props.hoverReveal &&
    'lg:opacity-0 lg:group-hover:opacity-100 lg:focus-visible:opacity-100',
  props.disabled && 'disabled:opacity-50 disabled:cursor-not-allowed',
])
</script>

<template>
  <button type="button" :class="classes" :disabled="disabled">
    <span class="sr-only">{{ label }}</span>
    <slot />
  </button>
</template>
