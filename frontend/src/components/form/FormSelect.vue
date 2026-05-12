<script setup lang="ts">
import { ChevronDownIcon } from '@heroicons/vue/16/solid'

defineProps<{
  id: string
  label: string
  modelValue: string
  options: { value: string; label: string }[]
  required?: boolean
  disabled?: boolean
  autocomplete?: string
}>()

defineEmits<{
  'update:modelValue': [value: string]
}>()
</script>

<template>
  <div>
    <label :for="id" class="text-label text-ink block">
      {{ label }}
    </label>
    <div class="mt-2 grid grid-cols-1">
      <select
        :id="id"
        :value="modelValue"
        :required="required"
        :disabled="disabled"
        :autocomplete="autocomplete"
        class="focus:outline-focus col-start-1 row-start-1 w-full appearance-none rounded-md bg-gray-100 py-1.5 pr-8 pl-3 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 *:bg-white focus:outline-2 focus:-outline-offset-2 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:*:bg-stone-800"
        @change="
          $emit('update:modelValue', ($event.target as HTMLSelectElement).value)
        "
      >
        <option
          v-for="option in options"
          :key="option.value"
          :value="option.value"
        >
          {{ option.label }}
        </option>
      </select>
      <ChevronDownIcon
        class="pointer-events-none col-start-1 row-start-1 mr-2 size-5 self-center justify-self-end text-gray-400 sm:size-4"
        aria-hidden="true"
      />
    </div>
  </div>
</template>
