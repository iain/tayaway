<script setup lang="ts">
defineProps<{
  modelValue: string
  id?: string
  placeholder?: string
  disabled?: boolean
}>()

defineEmits<{
  'update:modelValue': [value: string]
}>()
</script>

<template>
  <div
    class="bg-surface-sunken focus-within:outline-focus outline-line flex items-center rounded-md px-3 outline-1 -outline-offset-1 focus-within:outline-2 focus-within:outline-offset-2"
  >
    <div class="text-ink-muted shrink-0 text-sm/6 select-none">€</div>
    <input
      :id="id"
      type="text"
      inputmode="decimal"
      :value="modelValue"
      :placeholder="placeholder ?? '0.00'"
      :disabled="disabled"
      class="text-ink placeholder:text-ink-placeholder block min-w-0 grow bg-transparent py-1.5 pr-3 pl-1 text-sm/6 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50"
      @input="
        $emit('update:modelValue', ($event.target as HTMLInputElement).value)
      "
    />
  </div>
</template>
