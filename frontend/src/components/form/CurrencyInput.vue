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
    class="focus-within:outline-focus flex items-center rounded-md bg-gray-100 px-3 outline-1 -outline-offset-1 outline-gray-300 focus-within:outline-2 focus-within:-outline-offset-2 dark:bg-white/5 dark:outline-white/10"
  >
    <div
      class="shrink-0 text-sm/6 text-gray-500 select-none dark:text-stone-400"
    >
      €
    </div>
    <input
      :id="id"
      type="text"
      inputmode="decimal"
      :value="modelValue"
      :placeholder="placeholder ?? '0.00'"
      :disabled="disabled"
      class="block min-w-0 grow bg-transparent py-1.5 pr-3 pl-1 text-sm/6 text-gray-900 placeholder:text-gray-400 focus:outline-none dark:text-white dark:placeholder:text-stone-500"
      @input="
        $emit('update:modelValue', ($event.target as HTMLInputElement).value)
      "
    />
  </div>
</template>
