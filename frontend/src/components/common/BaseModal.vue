<script setup lang="ts">
import { ref, watch } from 'vue'
import { XMarkIcon } from '@heroicons/vue/24/outline'

const props = defineProps<{
  open: boolean
  title: string
  size?: 'sm' | 'md' | 'lg' | 'xl' | '2xl'
}>()

const emit = defineEmits<{
  close: []
}>()

const dialogRef = ref<HTMLDialogElement | null>(null)

watch(() => props.open, (isOpen) => {
  if (isOpen) {
    dialogRef.value?.showModal()
  } else {
    dialogRef.value?.close()
  }
})

function handleClose(): void {
  emit('close')
}

const sizeClasses: Record<string, string> = {
  sm: 'sm:max-w-sm',
  md: 'sm:max-w-md',
  lg: 'sm:max-w-lg',
  xl: 'sm:max-w-xl',
  '2xl': 'sm:max-w-2xl',
}
</script>

<template>
  <dialog
    ref="dialogRef"
    :class="[
      'm-auto rounded-lg bg-white dark:bg-gray-900 p-6 text-left shadow-xl backdrop:bg-gray-500/75 backdrop:backdrop-blur-[2px] dark:backdrop:bg-gray-900/75 sm:w-full',
      sizeClasses[size ?? 'md']
    ]"
    @close="handleClose"
  >
    <div class="absolute right-0 top-0 pr-4 pt-4">
      <button
        type="button"
        class="rounded-md bg-white dark:bg-gray-900 text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300 focus:outline-none focus:ring-2 focus:ring-rose-500 focus:ring-offset-2 focus:ring-offset-white dark:focus:ring-offset-gray-900"
        @click="handleClose"
      >
        <span class="sr-only">Close</span>
        <XMarkIcon
          class="size-6"
          aria-hidden="true"
        />
      </button>
    </div>

    <h3 class="text-lg font-semibold text-gray-900 dark:text-white mb-6">
      {{ title }}
    </h3>

    <slot />
  </dialog>
</template>
