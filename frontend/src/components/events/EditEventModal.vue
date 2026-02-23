<script setup lang="ts">
import { ref, watch } from 'vue'
import BaseModal from '@/components/common/BaseModal.vue'
import FormInput from '@/components/form/FormInput.vue'
import FormTextarea from '@/components/form/FormTextarea.vue'
import FormActions from '@/components/form/FormActions.vue'

type EditField = 'name' | 'description' | 'dates'

const props = defineProps<{
  open: boolean
  field: EditField
  currentName: string
  currentDescription: string | null
  currentStartDate: string | null
  currentEndDate: string | null
  loading?: boolean
}>()

const emit = defineEmits<{
  close: []
  save: [
    data: {
      name: string
      description: string | undefined
      startDate: string | null
      endDate: string | null
    },
  ]
}>()

const name = ref('')
const description = ref('')
const startDate = ref('')
const endDate = ref('')

watch(
  () => props.open,
  (isOpen) => {
    if (isOpen) {
      name.value = props.currentName
      description.value = props.currentDescription ?? ''
      startDate.value = props.currentStartDate ?? ''
      endDate.value = props.currentEndDate ?? ''
    }
  }
)

const titles: Record<EditField, string> = {
  name: 'Edit Title',
  description: 'Edit Description',
  dates: 'Edit Dates',
}

function handleSave(): void {
  emit('save', {
    name: name.value.trim() || props.currentName,
    description: description.value.trim() || undefined,
    startDate: startDate.value || null,
    endDate: endDate.value || null,
  })
}

function handleClose(): void {
  emit('close')
}
</script>

<template>
  <BaseModal :open="open" :title="titles[field]" @close="handleClose">
    <form class="space-y-4" @submit.prevent="handleSave">
      <FormInput
        v-if="field === 'name'"
        id="edit-event-name"
        v-model="name"
        label="Title"
        placeholder="Enter event name"
        autocomplete="off"
        autofocus
        required
        :maxlength="255"
        :disabled="loading"
        data-testid="edit-name-input"
      />

      <FormTextarea
        v-if="field === 'description'"
        id="edit-event-description"
        v-model="description"
        label="Description"
        placeholder="Enter event description"
        :rows="4"
        autofocus
        :disabled="loading"
        data-testid="edit-description-input"
      />

      <div v-if="field === 'dates'" class="grid grid-cols-2 gap-4">
        <FormInput
          id="edit-event-start-date"
          v-model="startDate"
          type="date"
          label="Start date"
          :disabled="loading"
          data-testid="edit-start-date-input"
        />
        <FormInput
          id="edit-event-end-date"
          v-model="endDate"
          type="date"
          label="End date"
          :disabled="loading"
          data-testid="edit-end-date-input"
        />
      </div>

      <FormActions
        submit-label="Save"
        :loading="loading"
        @cancel="handleClose"
      />
    </form>
  </BaseModal>
</template>
