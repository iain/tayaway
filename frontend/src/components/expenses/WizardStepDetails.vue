<script setup lang="ts">
import { ref } from 'vue'
import FormInput from '@/components/form/FormInput.vue'

defineProps<{
  disabled: boolean
}>()

const description = defineModel<string>('description', { required: true })
const amount = defineModel<string>('amount', { required: true })

const amountError = ref('')

function formatAmount(): void {
  const raw = amount.value.trim().replace(',', '.')
  amountError.value = ''

  if (!raw) return

  const num = parseFloat(raw)
  if (isNaN(num) || num < 0) {
    amountError.value = 'Enter a valid amount'
    return
  }
  if (num === 0) {
    amountError.value = 'Amount must be greater than zero'
    return
  }

  amount.value = num.toFixed(2)
}
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

    <div>
      <FormInput
        id="expense-amount"
        v-model="amount"
        label="Amount"
        placeholder="0.00"
        data-testid="expense-amount-input"
        prefix="€"
        inputmode="decimal"
        :disabled="disabled"
        @blur="formatAmount"
      />
      <p v-if="amountError" class="mt-1 text-xs text-red-600 dark:text-red-400">
        {{ amountError }}
      </p>
    </div>
  </div>
</template>
