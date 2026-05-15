<script setup lang="ts">
import AppButton from '@/components/common/AppButton.vue'

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
      :disabled="loading"
      class="min-h-[44px] px-3 py-2 text-sm/6 font-semibold text-ink disabled:cursor-not-allowed disabled:opacity-50 sm:min-h-0"
      @click="$emit('cancel')"
    >
      {{ cancelLabel ?? 'Cancel' }}
    </button>
    <AppButton
      type="submit"
      :data-testid="submitTestid ?? 'submit-button'"
      :disabled="disabled"
      :loading="loading"
      :loading-label="loadingLabel ?? 'Saving...'"
      :autofocus="autofocusSubmit"
    >
      {{ submitLabel ?? 'Save' }}
    </AppButton>
  </div>
</template>
