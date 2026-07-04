<script setup lang="ts">
import { useTemplateRef } from 'vue'

const props = defineProps<{
  padded?: boolean
  as?: string
  interactive?: boolean
  variant?: 'default' | 'action' | 'urgent' | 'self'
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
        'hover:ring-ring-hover focus-visible:outline-focus cursor-pointer transition-[box-shadow,transform,filter] hover:ring-2 focus-visible:outline-2 focus-visible:outline-offset-2 active:scale-[0.99] active:brightness-95 dark:active:brightness-110':
          interactive,
      },
      variant === 'urgent'
        ? 'bg-surface-urgent ring-ring-urgent ring-2'
        : variant === 'action'
          ? 'bg-surface-action ring-ring-action ring-2'
          : variant === 'self'
            ? 'bg-amber-300/30 ring-2 ring-amber-400 dark:bg-amber-400/15 dark:ring-amber-500/50'
            : 'bg-surface ring-ring-hairline ring-1 dark:shadow-[0_2px_8px_rgba(0,0,0,0.25),inset_0_1px_0_rgba(255,255,255,0.06)]',
    ]"
    :tabindex="interactive ? 0 : undefined"
    :role="interactive ? 'button' : undefined"
    @keydown="handleKeydown"
  >
    <slot />
  </component>
</template>
