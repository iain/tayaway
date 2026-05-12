<script setup lang="ts">
import { useAttrs } from 'vue'

defineOptions({
  inheritAttrs: false,
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
    <label :for="id" class="text-label text-ink block">
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
        class="focus:outline-focus block w-full rounded-md bg-gray-100 px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 sm:text-sm/6 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-stone-500"
        @input="
          $emit(
            'update:modelValue',
            ($event.target as HTMLTextAreaElement).value
          )
        "
      />
    </div>
    <p v-if="hint" class="text-ink-muted mt-3 text-sm/6">
      {{ hint }}
    </p>
  </div>
</template>
