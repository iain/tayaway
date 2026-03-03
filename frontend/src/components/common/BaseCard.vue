<script setup lang="ts">
defineProps<{
  padded?: boolean
  as?: string
  interactive?: boolean
}>()
</script>

<template>
  <component
    :is="as ?? 'div'"
    class="rounded-lg bg-white shadow ring-1 ring-black/5 dark:bg-stone-800 dark:shadow-[0_2px_8px_rgba(0,0,0,0.25),inset_0_1px_0_rgba(255,255,255,0.06)] dark:ring-white/[0.06]"
    :class="{
      'p-6': padded,
      'cursor-pointer transition-all hover:ring-2 hover:ring-rose-500':
        interactive,
    }"
  >
    <slot />
  </component>
</template>
