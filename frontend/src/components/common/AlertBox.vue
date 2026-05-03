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
    'border border-red-200 bg-red-50 text-red-800 dark:border-red-800 dark:bg-red-900/30 dark:text-red-400',
  warning:
    'border border-amber-200 bg-amber-50 text-amber-800 dark:border-amber-800 dark:bg-amber-950/30 dark:text-amber-300',
  success:
    'border border-green-200 bg-green-50 text-green-800 dark:border-green-800 dark:bg-green-900/20 dark:text-green-400',
}

const iconClasses: Record<string, string> = {
  error: 'text-red-600 dark:text-red-400',
  warning: 'text-amber-600 dark:text-amber-400',
  success: 'text-green-600 dark:text-green-400',
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
