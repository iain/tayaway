<script setup lang="ts">
import { ref, watch } from 'vue'
import BaseModal from '@/components/common/BaseModal.vue'
import FormInput from '@/components/form/FormInput.vue'
import FormTextarea from '@/components/form/FormTextarea.vue'

const props = defineProps<{
  open: boolean
  loading?: boolean
}>()

const emit = defineEmits<{
  close: []
  save: [name: string, description: string]
}>()

const name = ref('')
const description = ref('')

watch(() => props.open, (isOpen) => {
  if (isOpen) {
    name.value = ''
    description.value = ''
  }
})

function handleSave(): void {
  if (name.value.trim()) {
    emit('save', name.value.trim(), description.value.trim())
  }
}

function handleClose(): void {
  emit('close')
}
</script>

<template>
  <BaseModal
    :open="open"
    title="New Event"
    @close="handleClose"
  >
    <form
      class="space-y-4"
      @submit.prevent="handleSave"
    >
      <FormInput
        id="event-name"
        v-model="name"
        label="Name"
        placeholder="Enter event name"
        autocomplete="off"
        autofocus
        required
        :maxlength="255"
        :disabled="loading"
      />
      <FormTextarea
        id="event-description"
        v-model="description"
        label="Description (optional)"
        placeholder="Enter event description"
        :rows="3"
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
          :disabled="!name.trim() || loading"
        >
          {{ loading ? 'Creating...' : 'Create Event' }}
        </button>
      </div>
    </form>
  </BaseModal>
</template>
