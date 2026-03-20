<script setup lang="ts">
import FormInput from '@/components/form/FormInput.vue'

defineProps<{
  disabled: boolean
}>()

const description = defineModel<string>('description', { required: true })
const amount = defineModel<string>('amount', { required: true })
</script>

<template>
  <div class="space-y-4">
    <FormInput
      id="expense-description"
      v-model="description"
      label="Description"
      placeholder="What was this expense for?"
      data-testid="expense-description-input"
      autofocus
      :disabled="disabled"
    />

    <FormInput
      id="expense-amount"
      v-model="amount"
      label="Amount"
      placeholder="0.00"
      data-testid="expense-amount-input"
      prefix="€"
      inputmode="decimal"
      :disabled="disabled"
    />
  </div>
</template>
