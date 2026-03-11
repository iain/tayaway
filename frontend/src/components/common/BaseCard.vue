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
    class="rounded-lg shadow ring-1"
    :class="[
      {
        'p-6': padded,
        'cursor-pointer transition-all hover:ring-2 hover:ring-rose-500':
          interactive,
      },
      variant === 'urgent'
        ? 'border-l-4 border-l-red-500 bg-red-50/50 ring-red-200 dark:border-l-red-400 dark:bg-red-950/20 dark:ring-red-900/40'
        : variant === 'action'
          ? 'border-l-4 border-l-amber-400 bg-amber-50/30 ring-amber-200 dark:border-l-amber-500 dark:bg-amber-950/15 dark:ring-amber-900/30'
          : 'bg-white ring-black/5 dark:bg-stone-800 dark:shadow-[0_2px_8px_rgba(0,0,0,0.25),inset_0_1px_0_rgba(255,255,255,0.06)] dark:ring-white/[0.06]',
    ]"
    :tabindex="interactive ? 0 : undefined"
    :role="interactive ? 'button' : undefined"
    @keydown="handleKeydown"
  >
    <slot />
  </component>
</template>
