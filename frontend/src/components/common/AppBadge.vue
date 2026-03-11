<script setup lang="ts">
const props = withDefaults(
  defineProps<{
    variant?:
      | 'green'
      | 'red'
      | 'yellow'
      | 'amber'
      | 'blue'
      | 'gray'
    size?: 'xs' | 'sm'
  }>(),
  {
    variant: 'gray',
    size: 'xs',
  }
)

const variantClasses: Record<string, string> = {
  green:
    'bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-300',
  red: 'bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-400',
  yellow:
    'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-400',
  amber:
    'bg-amber-100 text-amber-800 dark:bg-amber-900/30 dark:text-amber-400',
  blue: 'bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-400',
  gray: 'bg-gray-100 text-gray-600 dark:bg-stone-700 dark:text-stone-300',
}

const sizeClasses: Record<string, string> = {
  xs: 'px-2 py-0.5 text-xs',
  sm: 'px-2.5 py-0.5 text-xs',
}
</script>

<template>
  <span
    class="inline-flex shrink-0 items-center gap-1 rounded-full font-medium"
    :class="[variantClasses[props.variant], sizeClasses[props.size]]"
  >
    <slot />
  </span>
</template>
