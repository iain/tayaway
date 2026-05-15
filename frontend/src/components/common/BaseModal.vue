<script setup lang="ts">
import { onMounted, ref, useId, watch } from 'vue'
import { XMarkIcon } from '@heroicons/vue/24/outline'

const props = defineProps<{
  open: boolean
  title: string
  size?: 'sm' | 'md' | 'lg' | 'xl' | '2xl'
  preventClose?: boolean
}>()

// Wire the dialog's accessible name to the heading text so screen readers
// announce the title on open. Native <dialog> doesn't do this automatically.
const titleId = useId()

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
    :aria-labelledby="titleId"
    :class="[
      'modal-dialog bg-surface m-auto rounded-lg p-4 text-left shadow-xl ring-1 ring-black/10 backdrop:bg-gray-500/85 sm:w-full sm:p-6 dark:ring-white/10 dark:backdrop:bg-stone-900/80',
      sizeClasses[size ?? 'md'],
    ]"
    @close="handleClose"
    @cancel="handleCancel"
  >
    <div class="absolute top-0 right-0 pt-4 pr-4">
      <button
        type="button"
        :disabled="preventClose"
        class="bg-surface text-ink-muted hover:text-ink focus-visible:outline-focus rounded-md focus-visible:outline-2 focus-visible:outline-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
        @click="handleClose"
      >
        <span class="sr-only">Close</span>
        <XMarkIcon class="size-6" aria-hidden="true" />
      </button>
    </div>

    <h3 :id="titleId" class="text-section-heading text-ink mb-heading">
      {{ title }}
    </h3>

    <slot />
  </dialog>
</template>

<style scoped>
.modal-dialog {
  opacity: 0;
  transform: translateY(8px) scale(0.98);
  transition:
    opacity 200ms cubic-bezier(0.25, 1, 0.5, 1),
    transform 200ms cubic-bezier(0.25, 1, 0.5, 1),
    overlay 200ms allow-discrete,
    display 200ms allow-discrete;
}

.modal-dialog[open] {
  opacity: 1;
  transform: translateY(0) scale(1);
}

.modal-dialog::backdrop {
  opacity: 0;
  transition:
    opacity 200ms cubic-bezier(0.25, 1, 0.5, 1),
    overlay 200ms allow-discrete,
    display 200ms allow-discrete;
}

.modal-dialog[open]::backdrop {
  opacity: 1;
}

@starting-style {
  .modal-dialog[open] {
    opacity: 0;
    transform: translateY(8px) scale(0.98);
  }

  .modal-dialog[open]::backdrop {
    opacity: 0;
  }
}

@media (prefers-reduced-motion: reduce) {
  .modal-dialog,
  .modal-dialog::backdrop {
    transition-duration: 0.01ms;
  }
}
</style>
