<script setup lang="ts">
import { computed } from 'vue'
import { LockClosedIcon } from '@heroicons/vue/20/solid'

const props = withDefaults(
  defineProps<{
    state: 'on' | 'off' | 'forced'
    label: string
    saving?: boolean
    forcedReason?: string
  }>(),
  {
    saving: false,
    forcedReason: undefined,
  }
)

defineEmits<{
  toggle: []
}>()

const stateClasses = computed(() => {
  if (props.state === 'forced') {
    return 'bg-amber-100 text-amber-900 ring-amber-200 cursor-not-allowed dark:bg-amber-900/30 dark:text-amber-200 dark:ring-amber-700/40'
  }
  if (props.state === 'on') {
    return 'bg-amber-100 text-amber-900 ring-amber-200 hover:bg-amber-200/80 hover:ring-amber-300 dark:bg-amber-900/30 dark:text-amber-200 dark:ring-amber-700/40 dark:hover:bg-amber-900/50 dark:hover:ring-amber-700/60'
  }
  return 'bg-transparent text-gray-500 ring-gray-300 hover:bg-gray-50 hover:text-gray-700 hover:ring-gray-400 dark:text-stone-400 dark:ring-stone-600 dark:hover:bg-stone-700/50 dark:hover:text-stone-200 dark:hover:ring-stone-500'
})
</script>

<template>
  <button
    type="button"
    class="inline-flex min-h-9 cursor-pointer items-center gap-1.5 rounded-full px-3.5 text-sm font-medium ring-1 transition-colors ring-inset focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
    :class="[stateClasses, saving && 'animate-pulse']"
    :aria-pressed="state === 'on' || state === 'forced'"
    :aria-disabled="state === 'forced' ? true : undefined"
    :tabindex="state === 'forced' ? -1 : undefined"
    :title="state === 'forced' ? forcedReason : undefined"
    @click="state !== 'forced' && $emit('toggle')"
  >
    <LockClosedIcon
      v-if="state === 'forced'"
      class="size-3.5"
      aria-hidden="true"
    />
    <span>{{ label }}</span>
  </button>
</template>
