<script setup lang="ts">
import { useAttrs } from 'vue'

defineOptions({
  inheritAttrs: false
})

defineProps<{
  id: string
  label: string
  modelValue: string
  type?: string
  placeholder?: string
  required?: boolean
  disabled?: boolean
  maxlength?: number
  autocomplete?: string
  prefix?: string
}>()

defineEmits<{
  'update:modelValue': [value: string]
}>()

const attrs = useAttrs()
</script>

<template>
  <div>
    <label
      :for="id"
      class="block text-sm/6 font-medium text-white"
    >
      {{ label }}
    </label>
    <div class="mt-2">
      <div
        v-if="prefix"
        class="flex items-center rounded-md bg-white/5 pl-3 outline-1 -outline-offset-1 outline-white/10 focus-within:outline-2 focus-within:-outline-offset-2 focus-within:outline-indigo-500"
      >
        <div class="shrink-0 text-base text-gray-400 select-none sm:text-sm/6">
          {{ prefix }}
        </div>
        <input
          :id="id"
          :type="type ?? 'text'"
          :value="modelValue"
          :placeholder="placeholder"
          :required="required"
          :disabled="disabled"
          :maxlength="maxlength"
          :autocomplete="autocomplete"
          v-bind="attrs"
          class="block min-w-0 grow bg-transparent py-1.5 pr-3 pl-1 text-base text-white placeholder:text-gray-500 focus:outline-none sm:text-sm/6"
          @input="$emit('update:modelValue', ($event.target as HTMLInputElement).value)"
        >
      </div>
      <input
        v-else
        :id="id"
        :type="type ?? 'text'"
        :value="modelValue"
        :placeholder="placeholder"
        :required="required"
        :disabled="disabled"
        :maxlength="maxlength"
        :autocomplete="autocomplete"
        v-bind="attrs"
        class="block w-full rounded-md bg-white/5 px-3 py-1.5 text-base text-white outline-1 -outline-offset-1 outline-white/10 placeholder:text-gray-500 focus:outline-2 focus:-outline-offset-2 focus:outline-indigo-500 sm:text-sm/6"
        @input="$emit('update:modelValue', ($event.target as HTMLInputElement).value)"
      >
    </div>
  </div>
</template>
