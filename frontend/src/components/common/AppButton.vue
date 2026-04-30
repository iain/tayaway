<script setup lang="ts">
import { computed } from 'vue'
import type { RouteLocationRaw } from 'vue-router'

const props = withDefaults(
  defineProps<{
    variant?:
      | 'primary'
      | 'secondary'
      | 'amber'
      | 'cyan-soft'
      | 'amber-soft'
      | 'danger'
    size?: 'sm' | 'md' | 'lg'
    disabled?: boolean
    loading?: boolean
    loadingLabel?: string
    to?: RouteLocationRaw
    type?: 'button' | 'submit'
    fullWidth?: boolean
  }>(),
  {
    variant: 'primary',
    size: 'md',
    loadingLabel: undefined,
    to: undefined,
    type: 'button',
  }
)

defineEmits<{
  click: [event: MouseEvent]
}>()

const variantClasses: Record<string, string> = {
  primary:
    'bg-rose-600 text-white hover:bg-rose-500 focus-visible:outline-rose-500',
  secondary:
    'bg-gray-100 text-gray-700 hover:bg-gray-200 dark:bg-stone-700 dark:text-stone-300 dark:hover:bg-stone-600',
  amber:
    'bg-amber-600 text-white hover:bg-amber-700 dark:bg-amber-700 dark:hover:bg-amber-600',
  'cyan-soft':
    'bg-cyan-100 text-cyan-700 hover:bg-cyan-200 dark:bg-cyan-900/30 dark:text-cyan-300 dark:hover:bg-cyan-900/50',
  'amber-soft':
    'bg-amber-200 text-amber-900 hover:bg-amber-300 dark:bg-amber-900/50 dark:text-amber-200 dark:hover:bg-amber-900/70',
  danger:
    'bg-red-600 text-white hover:bg-red-500 focus-visible:outline-rose-500',
}

const sizeClasses: Record<string, string> = {
  sm: 'px-3 py-1.5 text-sm',
  md: 'px-3 py-2 text-sm',
  lg: 'px-6 py-4 text-lg',
}

const classes = computed(() => [
  'inline-flex cursor-pointer items-center justify-center gap-2 rounded-md font-semibold shadow-sm transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 disabled:cursor-not-allowed disabled:opacity-50',
  variantClasses[props.variant],
  sizeClasses[props.size],
  props.fullWidth && 'w-full',
])

const tag = computed(() => (props.to ? 'router-link' : 'button'))

const buttonAttrs = computed(() => {
  if (props.to) {
    return { to: props.to }
  }
  return {
    type: props.type,
    disabled: props.disabled || props.loading,
  }
})
</script>

<template>
  <component
    :is="tag"
    v-bind="buttonAttrs"
    :class="classes"
    @click="$emit('click', $event)"
  >
    <slot v-if="!loading" />
    <template v-else>
      <svg
        class="size-4 animate-spin"
        aria-hidden="true"
        xmlns="http://www.w3.org/2000/svg"
        fill="none"
        viewBox="0 0 24 24"
      >
        <circle
          class="opacity-25"
          cx="12"
          cy="12"
          r="10"
          stroke="currentColor"
          stroke-width="4"
        />
        <path
          class="opacity-75"
          fill="currentColor"
          d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
        />
      </svg>
      {{ loadingLabel ?? 'Loading...' }}
    </template>
  </component>
</template>
