<script setup lang="ts">
import { ref, watch } from 'vue'
import BaseModal from '@/components/common/BaseModal.vue'
import FormInput from '@/components/form/FormInput.vue'
import FormActions from '@/components/form/FormActions.vue'

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

      <FormActions
        submit-label="Save"
        :loading="loading"
        :disabled="!name.trim()"
        @cancel="handleClose"
      />
    </form>
  </BaseModal>
</template>
