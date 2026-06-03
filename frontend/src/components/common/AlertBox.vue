<script setup lang="ts">
import { computed, type Component } from 'vue'

const props = withDefaults(
  defineProps<{
    variant?: 'error' | 'warning' | 'success'
    icon?: Component
  }>(),
  {
    variant: 'error',
    icon: undefined,
  }
)

const variantClasses: Record<string, string> = {
  error:
    'border border-state-danger-fill bg-state-danger-fill text-state-danger-ink',
  warning:
    'border border-state-warning-fill bg-state-warning-fill text-state-warning-ink',
  success:
    'border border-state-success-fill bg-state-success-fill text-state-success-ink',
}

const iconClasses: Record<string, string> = {
  error: 'text-state-danger-ink',
  warning: 'text-state-warning-ink',
  success: 'text-state-success-ink',
}

// Errors interrupt with `role="alert"`; success and warning queue politely
// behind whatever the screen reader is currently saying via `role="status"`.
const semanticRole = computed(() =>
  props.variant === 'error' ? 'alert' : 'status'
)
</script>

<template>
  <div
    class="rounded-md p-4"
    :class="variantClasses[variant]"
    :role="semanticRole"
  >
    <div v-if="icon" class="flex items-start gap-3">
      <component
        :is="icon"
        class="mt-0.5 size-5 shrink-0"
        :class="iconClasses[variant]"
      />
      <div class="min-w-0 flex-1">
        <slot />
      </div>
    </div>
    <slot v-else />
  </div>
</template>
