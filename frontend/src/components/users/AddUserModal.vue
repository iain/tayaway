<script setup lang="ts">
import { ref, watch } from 'vue'
import BaseModal from '@/components/common/BaseModal.vue'
import FormInput from '@/components/form/FormInput.vue'

const props = defineProps<{
  open: boolean
  loading?: boolean
}>()

const emit = defineEmits<{
  close: []
  save: [name: string, email: string]
}>()

const name = ref('')
const email = ref('')

watch(() => props.open, (isOpen) => {
  if (isOpen) {
    name.value = ''
    email.value = ''
  }
})

function handleSave(): void {
  if (email.value.trim()) {
    emit('save', name.value.trim(), email.value.trim())
  }
}

function handleClose(): void {
  emit('close')
}
</script>

<template>
  <BaseModal
    :open="open"
    title="Add New User"
    @close="handleClose"
  >
    <form
      class="space-y-4"
      @submit.prevent="handleSave"
    >
      <FormInput
        id="user-name"
        v-model="name"
        label="Name"
        placeholder="Enter name (optional)"
        autocomplete="name"
        autofocus
        :disabled="loading"
      />
      <FormInput
        id="user-email"
        v-model="email"
        label="Email"
        type="email"
        placeholder="Enter email"
        autocomplete="email"
        required
        :disabled="loading"
      />

      <div class="mt-6 flex items-center justify-end gap-x-6">
        <button
          type="button"
          class="text-sm/6 font-semibold text-gray-900 dark:text-white"
          :disabled="loading"
          @click="handleClose"
        >
          Cancel
        </button>
        <button
          type="submit"
          data-testid="modal-save-button"
          class="rounded-md bg-rose-500 px-3 py-2 text-sm font-semibold text-white hover:bg-rose-400 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-rose-500 disabled:opacity-50 disabled:cursor-not-allowed"
          :disabled="!email.trim() || loading"
        >
          {{ loading ? 'Adding...' : 'Add User' }}
        </button>
      </div>
    </form>
  </BaseModal>
</template>
