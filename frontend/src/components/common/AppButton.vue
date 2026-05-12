<script setup lang="ts">
import { computed } from 'vue'
import type { RouteLocationRaw } from 'vue-router'

const props = withDefaults(
  defineProps<{
    variant?:
      | 'primary'
      | 'secondary'
      | 'amber'
      | 'inflow'
      | 'outflow'
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
  primary: 'bg-rose-600 text-white hover:bg-rose-500',
  secondary:
    'bg-btn-secondary-fill text-btn-secondary-ink hover:bg-btn-secondary-fill-hover',
  amber: 'bg-amber-700 text-white hover:bg-amber-800',
  inflow:
    'bg-btn-inflow-fill text-btn-inflow-ink hover:bg-btn-inflow-fill-hover',
  outflow:
    'bg-btn-outflow-fill text-btn-outflow-ink hover:bg-btn-outflow-fill-hover',
  danger: 'bg-red-700 text-white hover:bg-red-600',
}

const sizeClasses: Record<string, string> = {
  sm: 'px-3 py-1.5 text-sm',
  md: 'px-3 py-2 text-sm',
  lg: 'px-6 py-4 text-lg',
}

const classes = computed(() => [
  'inline-flex cursor-pointer items-center justify-center gap-2 rounded-md font-semibold shadow-sm transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus disabled:cursor-not-allowed disabled:opacity-50',
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
