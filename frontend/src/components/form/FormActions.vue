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
      class="text-sm/6 font-semibold text-gray-900 dark:text-white"
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
