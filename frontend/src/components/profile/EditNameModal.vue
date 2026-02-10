<script setup lang="ts">
import { ref, watch } from 'vue'
import BaseModal from '@/components/common/BaseModal.vue'
import FormInput from '@/components/form/FormInput.vue'

const props = defineProps<{
  open: boolean
  loading?: boolean
  currentName: string | null
}>()

const emit = defineEmits<{
  close: []
  save: [name: string]
}>()

const name = ref('')

watch(
  () => props.open,
  (isOpen) => {
    if (isOpen) {
      name.value = props.currentName ?? ''
    }
  }
)

function handleSave(): void {
  if (name.value.trim()) {
    emit('save', name.value.trim())
  }
}

function handleClose(): void {
  emit('close')
}
</script>

<template>
  <BaseModal :open="open" title="Edit Name" @close="handleClose">
    <form class="space-y-4" @submit.prevent="handleSave">
      <FormInput
        id="profile-name"
        v-model="name"
        label="Name"
        placeholder="Enter your name"
        autocomplete="name"
        autofocus
        required
        :maxlength="255"
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
          class="rounded-md bg-rose-500 px-3 py-2 text-sm font-semibold text-white hover:bg-rose-400 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-rose-500 disabled:cursor-not-allowed disabled:opacity-50"
          :disabled="!name.trim() || loading"
        >
          {{ loading ? 'Saving...' : 'Save' }}
        </button>
      </div>
    </form>
  </BaseModal>
</template>
