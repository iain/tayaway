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
  save: [name: string, email: string]
}>()

const name = ref('')
const email = ref('')

watch(
  () => props.open,
  (isOpen) => {
    if (isOpen) {
      name.value = ''
      email.value = ''
    }
  }
)

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
  <BaseModal :open="open" title="Add New Member" @close="handleClose">
    <form class="space-y-4" @submit.prevent="handleSave">
      <FormInput
        id="member-name"
        v-model="name"
        label="Name"
        placeholder="Enter name (optional)"
        autocomplete="name"
        autofocus
        :disabled="loading"
      />
      <FormInput
        id="member-email"
        v-model="email"
        label="Email"
        type="email"
        placeholder="Enter email"
        autocomplete="email"
        required
        :disabled="loading"
      />

      <FormActions
        submit-label="Add Member"
        loading-label="Adding..."
        :loading="loading"
        :disabled="!email.trim()"
        @cancel="handleClose"
      />
    </form>
  </BaseModal>
</template>
