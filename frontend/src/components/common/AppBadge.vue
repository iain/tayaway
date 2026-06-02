<script setup lang="ts">
const props = withDefaults(
  defineProps<{
    variant?: 'success' | 'danger' | 'warning' | 'pending' | 'info' | 'neutral'
    size?: 'xs' | 'sm'
  }>(),
  {
    variant: 'neutral',
    size: 'xs',
  }
)

const variantClasses: Record<string, string> = {
  success: 'bg-state-success-fill text-state-success-ink',
  danger: 'bg-state-danger-fill text-state-danger-ink',
  warning: 'bg-state-warning-fill text-state-warning-ink',
  pending: 'bg-state-pending-fill text-state-pending-ink',
  info: 'bg-state-info-fill text-state-info-ink',
  neutral: 'bg-state-neutral-fill text-state-neutral-ink',
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
