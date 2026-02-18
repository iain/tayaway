<script setup lang="ts">
defineProps<{
  submitLabel?: string
  cancelLabel?: string
  loadingLabel?: string
  loading?: boolean
  disabled?: boolean
  submitTestid?: string
  autofocusSubmit?: boolean
}>()

defineEmits<{
  cancel: []
}>()
</script>

<template>
  <div class="mt-6 flex items-center justify-end gap-x-6">
    <button
      type="button"
      data-testid="cancel-button"
      class="text-sm/6 font-semibold text-gray-900 dark:text-white"
      @click="$emit('cancel')"
    >
      {{ cancelLabel ?? 'Cancel' }}
    </button>
    <button
      type="submit"
      :data-testid="submitTestid ?? 'submit-button'"
      :disabled="disabled || loading"
      :autofocus="autofocusSubmit"
      class="rounded-md bg-rose-500 px-3 py-2 text-sm font-semibold text-white hover:bg-rose-400 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-rose-500 disabled:cursor-not-allowed disabled:opacity-50"
    >
      {{ loading ? (loadingLabel ?? 'Saving...') : (submitLabel ?? 'Save') }}
    </button>
  </div>
</template>
