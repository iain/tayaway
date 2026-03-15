<script setup lang="ts">
import { onMounted, ref, watch } from 'vue'
import { XMarkIcon } from '@heroicons/vue/24/outline'

const props = defineProps<{
  open: boolean
  title: string
  size?: 'sm' | 'md' | 'lg' | 'xl' | '2xl'
  preventClose?: boolean
}>()

const emit = defineEmits<{
  close: []
}>()

const dialogRef = ref<HTMLDialogElement | null>(null)

onMounted(() => {
  if (props.open) {
    dialogRef.value?.showModal()
  }
})

watch(
  () => props.open,
  (isOpen) => {
    if (isOpen) {
      dialogRef.value?.showModal()
    } else {
      dialogRef.value?.close()
    }
  },
  { flush: 'post' }
)

function handleClose(): void {
  if (props.preventClose) return
  emit('close')
}

function handleCancel(e: Event): void {
  if (props.preventClose) {
    e.preventDefault()
  }
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
      'm-auto rounded-lg bg-white p-6 text-left shadow-xl ring-1 ring-black/10 backdrop:bg-gray-500/85 backdrop:backdrop-blur-[2px] sm:w-full dark:bg-stone-900 dark:ring-white/10 dark:backdrop:bg-stone-900/80',
      sizeClasses[size ?? 'md'],
    ]"
    @close="handleClose"
    @cancel="handleCancel"
  >
    <div class="absolute top-0 right-0 pt-4 pr-4">
      <button
        type="button"
        :disabled="preventClose"
        class="rounded-md bg-white text-gray-500 hover:text-gray-700 focus-visible:ring-2 focus-visible:ring-rose-500 focus-visible:ring-offset-2 focus-visible:ring-offset-white focus-visible:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:bg-stone-900 dark:text-stone-400 dark:hover:text-stone-300 dark:focus-visible:ring-offset-stone-900"
        @click="handleClose"
      >
        <span class="sr-only">Close</span>
        <XMarkIcon class="size-6" aria-hidden="true" />
      </button>
    </div>

    <h3 class="mb-6 text-lg font-semibold text-gray-900 dark:text-white">
      {{ title }}
    </h3>

    <slot />
  </dialog>
</template>
