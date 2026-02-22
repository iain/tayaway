<script setup lang="ts">
import { ref, watch } from 'vue'
import BaseModal from '@/components/common/BaseModal.vue'
import FormInput from '@/components/form/FormInput.vue'
import FormActions from '@/components/form/FormActions.vue'
import { useExpensesStore } from '@/stores/expenses'

const props = defineProps<{
  open: boolean
  eventId: string
}>()

const emit = defineEmits<{
  close: []
}>()

const expensesStore = useExpensesStore()

const description = ref('')
const amount = ref('')
const submitting = ref(false)

watch(
  () => props.open,
  (isOpen) => {
    if (isOpen) {
      description.value = ''
      amount.value = ''
    }
  }
)

async function handleSubmit(): Promise<void> {
  const desc = description.value.trim()
  const amt = parseFloat(amount.value)
  if (!desc || isNaN(amt) || amt <= 0) return

  submitting.value = true
  try {
    await expensesStore.createExpense(props.eventId, desc, amt)
    emit('close')
  } finally {
    submitting.value = false
  }
}

function handleClose(): void {
  emit('close')
}
</script>

<template>
  <BaseModal :open="open" title="Add Expense" @close="handleClose">
    <form class="space-y-4" @submit.prevent="handleSubmit">
      <FormInput
        id="expense-description"
        v-model="description"
        label="Description"
        placeholder="What was this expense for?"
        autofocus
        :disabled="submitting"
      />

      <FormInput
        id="expense-amount"
        v-model="amount"
        label="Amount"
        placeholder="0.00"
        prefix="€"
        inputmode="decimal"
        :disabled="submitting"
      />

      <FormActions
        submit-label="Add Expense"
        loading-label="Adding..."
        :loading="submitting"
        :disabled="!description.trim() || !(parseFloat(amount) > 0)"
        @cancel="handleClose"
      />
    </form>
  </BaseModal>
</template>
