<script setup lang="ts">
import { ref, watch } from 'vue'
import BaseModal from '@/components/common/BaseModal.vue'
import FormInput from '@/components/form/FormInput.vue'
import FormActions from '@/components/form/FormActions.vue'

const props = defineProps<{
  open: boolean
  loading?: boolean
  error?: string | null
}>()

const emit = defineEmits<{
  close: []
  submit: [email: string]
}>()

const email = ref('')

watch(
  () => props.open,
  (isOpen) => {
    if (isOpen) {
      email.value = ''
    }
  }
)

function handleSubmit(): void {
  if (email.value.trim()) {
    emit('submit', email.value.trim())
  }
}

function handleClose(): void {
  emit('close')
}
</script>

<template>
  <BaseModal :open="open" title="Change Email" @close="handleClose">
    <form class="space-y-4" @submit.prevent="handleSubmit">
      <p class="text-sm text-gray-500 dark:text-stone-400">
        Enter your new email address. We'll send a verification link to confirm
        the change.
      </p>

      <FormInput
        id="new-email"
        v-model="email"
        label="New email address"
        type="email"
        placeholder="Enter new email"
        autocomplete="email"
        autofocus
        required
        :disabled="loading"
      />

      <p v-if="error" class="text-sm text-red-600 dark:text-red-400">
        {{ error }}
      </p>

      <FormActions
        submit-label="Send verification link"
        loading-label="Sending..."
        :loading="loading"
        :disabled="!email.trim()"
        @cancel="handleClose"
      />
    </form>
  </BaseModal>
</template>
