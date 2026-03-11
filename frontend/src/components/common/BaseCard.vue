<script setup lang="ts">
import { useTemplateRef } from 'vue'

const props = defineProps<{
  padded?: boolean
  as?: string
  interactive?: boolean
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
    class="rounded-lg bg-white shadow ring-1 ring-black/5 dark:bg-stone-800 dark:shadow-[0_2px_8px_rgba(0,0,0,0.25),inset_0_1px_0_rgba(255,255,255,0.06)] dark:ring-white/[0.06]"
    :class="{
      'p-6': padded,
      'cursor-pointer transition-all hover:ring-2 hover:ring-rose-500':
        interactive,
    }"
    :tabindex="interactive ? 0 : undefined"
    :role="interactive ? 'button' : undefined"
    @keydown="handleKeydown"
  >
    <slot />
  </component>
</template>
