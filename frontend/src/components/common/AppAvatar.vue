<script setup lang="ts">
withDefaults(
  defineProps<{
    initials: string
    size?: 'xs' | 'sm' | 'md' | 'lg'
    variant?: 'neutral' | 'pending' | 'nav'
  }>(),
  {
    size: 'md',
    variant: 'neutral',
  }
)

const sizeClasses: Record<string, string> = {
  // 24px for inline ledger-row contexts where 32px (sm) is too large.
  xs: 'size-6 text-xs',
  sm: 'size-8 text-sm',
  md: 'size-10 text-sm',
  lg: 'size-12 text-lg',
}

const variantClasses: Record<string, string> = {
  neutral: 'bg-avatar-default-fill text-avatar-default-ink',
  pending: 'bg-avatar-pending-fill text-avatar-pending-ink',
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
