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
    <label :for="id" class="block text-sm/6 font-medium text-white">
      {{ label }}
    </label>
    <div class="mt-2 grid grid-cols-1">
      <select
        :id="id"
        :value="modelValue"
        :required="required"
        :disabled="disabled"
        :autocomplete="autocomplete"
        class="col-start-1 row-start-1 w-full appearance-none rounded-md bg-white/5 py-1.5 pr-8 pl-3 text-base text-white outline-1 -outline-offset-1 outline-white/10 *:bg-stone-800 focus:outline-2 focus:-outline-offset-2 focus:outline-rose-500 sm:text-sm/6"
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
