<script setup lang="ts">
import { computed } from 'vue'

const props = withDefaults(
  defineProps<{
    variant?: 'primary' | 'secondary' | 'danger'
    disabled?: boolean
  }>(),
  { variant: 'primary' }
)

defineEmits<{
  click: []
}>()

const variantClasses: Record<string, string> = {
  primary:
    'text-cyan-600 underline hover:text-cyan-700 dark:text-cyan-400 dark:hover:text-cyan-300',
  secondary:
    'text-gray-500 hover:text-gray-700 dark:text-stone-400 dark:hover:text-stone-300',
  danger:
    'text-red-600 hover:text-red-500 dark:text-red-400 dark:hover:text-red-300',
}

const variantClass = computed(() => variantClasses[props.variant])
</script>

<template>
  <button
    type="button"
    class="inline-flex cursor-pointer items-center gap-2 text-sm transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus disabled:cursor-not-allowed disabled:opacity-50"
    :class="variantClass"
    :disabled="disabled"
    @click="$emit('click')"
  >
    <slot />
  </button>
</template>
