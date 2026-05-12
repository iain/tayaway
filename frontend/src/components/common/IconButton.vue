<script setup lang="ts">
import { computed } from 'vue'

const props = withDefaults(
  defineProps<{
    variant?: 'default' | 'danger'
    label: string
    hoverReveal?: boolean
    disabled?: boolean
    // `default` enforces the 44pt HIG tap target on touch viewports for
    // standalone uses. `compact` drops it for use inside form rows where the
    // surrounding controls (small AppButton, TextButton) share a smaller row
    // height — matching their size keeps the row visually balanced and the
    // icon reads as part of the same action group.
    size?: 'default' | 'compact'
  }>(),
  {
    variant: 'default',
    size: 'default',
  }
)

const classes = computed(() => [
  'cursor-pointer rounded transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus inline-flex items-center justify-center',
  props.size === 'compact'
    ? 'p-1'
    : 'p-2 min-h-[44px] min-w-[44px] sm:min-h-0 sm:min-w-0 sm:p-1',
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
