<script setup lang="ts">
import { ref, watch } from 'vue'
import BaseModal from '@/components/common/BaseModal.vue'
import FormInput from '@/components/form/FormInput.vue'
import FormActions from '@/components/form/FormActions.vue'

const props = defineProps<{
  open: boolean
  loading?: boolean
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
      name.value = ''
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
  <BaseModal :open="open" title="New Task List" @close="handleClose">
    <form class="space-y-4" @submit.prevent="handleSave">
      <FormInput
        id="task-list-name"
        v-model="name"
        label="Name"
        placeholder="Enter list name"
        autofocus
        required
        :disabled="loading"
      />

      <FormActions
        submit-label="Create List"
        loading-label="Creating..."
        :loading="loading"
        :disabled="!name.trim()"
        @cancel="handleClose"
      />
    </form>
  </BaseModal>
</template>
