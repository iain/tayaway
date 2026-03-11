<script setup lang="ts">
withDefaults(
  defineProps<{
    initials: string
    size?: 'sm' | 'md' | 'lg'
    variant?: 'rose' | 'amber' | 'nav'
  }>(),
  {
    size: 'md',
    variant: 'rose',
  }
)

const sizeClasses: Record<string, string> = {
  sm: 'size-8 text-sm',
  md: 'size-10 text-sm',
  lg: 'size-12 text-lg',
}

const variantClasses: Record<string, string> = {
  rose: 'bg-rose-100 text-rose-600 dark:bg-rose-900/30 dark:text-rose-400',
  amber:
    'bg-amber-300 text-amber-900 dark:bg-amber-500 dark:text-amber-950',
  nav: 'bg-nav-hover text-nav-text',
}
</script>

<template>
  <span
    class="inline-flex shrink-0 items-center justify-center rounded-full font-semibold"
    :class="[sizeClasses[size], variantClasses[variant]]"
  >
    {{ initials }}
  </span>
</template>
