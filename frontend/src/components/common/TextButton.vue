<script setup lang="ts">
import { computed } from 'vue'

const props = withDefaults(
  defineProps<{
    variant?: 'primary' | 'secondary' | 'danger'
    disabled?: boolean
    href?: string
  }>(),
  { variant: 'primary', href: undefined }
)

defineEmits<{
  click: []
}>()

const variantClasses: Record<string, string> = {
  primary:
    'text-cyan-600 underline hover:text-cyan-700 dark:text-cyan-400 dark:hover:text-cyan-300',
  // secondary lifted to ink-muted so it clears WCAG AA 4.5:1 on both surface
  // and surface-page — text-gray-500 fell short on the page surface.
  secondary: 'text-ink-muted hover:text-ink',
  danger:
    'text-red-600 hover:text-red-500 dark:text-red-400 dark:hover:text-red-300',
}

const variantClass = computed(() => variantClasses[props.variant])
const tag = computed(() => (props.href ? 'a' : 'button'))
</script>

<template>
  <component
    :is="tag"
    v-bind="
      href
        ? { href, target: '_blank', rel: 'noopener' }
        : { type: 'button', disabled }
    "
    class="inline-flex cursor-pointer items-center gap-2 text-sm transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus disabled:cursor-not-allowed disabled:opacity-50"
    :class="variantClass"
    @click="$emit('click')"
  >
    <slot />
  </component>
</template>
