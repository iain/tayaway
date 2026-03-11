<script setup lang="ts">
import type { Component } from 'vue'

withDefaults(
  defineProps<{
    variant?: 'error' | 'warning'
    icon?: Component
  }>(),
  {
    variant: 'error',
    icon: undefined,
  }
)

const variantClasses: Record<string, string> = {
  error: 'bg-red-900/50 text-red-400',
  warning:
    'border border-amber-200 bg-amber-50 text-amber-800 dark:border-amber-800 dark:bg-amber-950/30 dark:text-amber-300',
}
</script>

<template>
  <div class="rounded-md p-4" :class="variantClasses[variant]">
    <div v-if="icon" class="flex items-start gap-3">
      <component
        :is="icon"
        class="mt-0.5 size-5 shrink-0"
        :class="
          variant === 'warning'
            ? 'text-amber-600 dark:text-amber-400'
            : 'text-red-400'
        "
      />
      <div class="min-w-0 flex-1">
        <slot />
      </div>
    </div>
    <slot v-else />
  </div>
</template>
