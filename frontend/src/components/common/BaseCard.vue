<script setup lang="ts">
import { useTemplateRef } from 'vue'

const props = defineProps<{
  padded?: boolean
  as?: string
  interactive?: boolean
  variant?: 'default' | 'action' | 'urgent'
}>()

const root = useTemplateRef<HTMLElement>('root')

function handleKeydown(event: KeyboardEvent) {
  if (!props.interactive) return
  if (event.key === 'Enter' || event.key === ' ') {
    event.preventDefault()
    root.value?.click()
  }
}
</script>

<template>
  <component
    :is="as ?? 'div'"
    ref="root"
    class="text-ink rounded-lg shadow"
    :class="[
      {
        'p-card': padded,
        'cursor-pointer transition-[box-shadow,transform,filter] hover:ring-2 hover:ring-ring-hover focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus active:scale-[0.99] active:brightness-95 dark:active:brightness-110':
          interactive,
      },
      variant === 'urgent'
        ? 'bg-surface-urgent ring-ring-urgent ring-2'
        : variant === 'action'
          ? 'bg-surface-action ring-ring-action ring-2'
          : 'bg-surface ring-ring-hairline ring-1 dark:shadow-[0_2px_8px_rgba(0,0,0,0.25),inset_0_1px_0_rgba(255,255,255,0.06)]',
    ]"
    :tabindex="interactive ? 0 : undefined"
    :role="interactive ? 'button' : undefined"
    @keydown="handleKeydown"
  >
    <slot />
  </component>
</template>
