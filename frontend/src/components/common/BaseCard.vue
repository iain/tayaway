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
    class="rounded-lg shadow"
    :class="[
      {
        'p-6': padded,
        'cursor-pointer transition-all hover:ring-2 hover:ring-rose-500 active:scale-[0.99] active:brightness-95':
          interactive,
      },
      variant === 'urgent'
        ? 'bg-red-50 ring-2 ring-red-300/60 dark:bg-red-950/30 dark:ring-red-800/50'
        : variant === 'action'
          ? 'bg-amber-50/60 ring-2 ring-amber-300/50 dark:bg-amber-950/20 dark:ring-amber-700/40'
          : 'bg-white ring-1 ring-black/5 dark:bg-stone-800 dark:shadow-[0_2px_8px_rgba(0,0,0,0.25),inset_0_1px_0_rgba(255,255,255,0.06)] dark:ring-white/[0.06]',
    ]"
    :tabindex="interactive ? 0 : undefined"
    :role="interactive ? 'button' : undefined"
    @keydown="handleKeydown"
  >
    <slot />
  </component>
</template>
