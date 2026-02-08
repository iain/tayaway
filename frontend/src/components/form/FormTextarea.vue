<script setup lang="ts">
import { useAttrs } from 'vue'

defineOptions({
  inheritAttrs: false
})

defineProps<{
  id: string
  label: string
  modelValue: string
  placeholder?: string
  required?: boolean
  disabled?: boolean
  rows?: number
  hint?: string
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
      <textarea
        :id="id"
        :value="modelValue"
        :placeholder="placeholder"
        :required="required"
        :disabled="disabled"
        :rows="rows ?? 3"
        v-bind="attrs"
        class="block w-full rounded-md bg-white/5 px-3 py-1.5 text-base text-white outline-1 -outline-offset-1 outline-white/10 placeholder:text-gray-500 focus:outline-2 focus:-outline-offset-2 focus:outline-rose-500 sm:text-sm/6"
        @input="$emit('update:modelValue', ($event.target as HTMLTextAreaElement).value)"
      />
    </div>
    <p
      v-if="hint"
      class="mt-3 text-sm/6 text-gray-400"
    >
      {{ hint }}
    </p>
  </div>
</template>
