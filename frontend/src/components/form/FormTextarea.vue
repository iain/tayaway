<script setup lang="ts">
import { computed, useAttrs } from 'vue'
import { ExclamationCircleIcon } from '@heroicons/vue/20/solid'

defineOptions({
  inheritAttrs: false,
})

const props = defineProps<{
  id: string
  label: string
  modelValue: string
  placeholder?: string
  required?: boolean
  disabled?: boolean
  rows?: number
  hint?: string
  error?: string
}>()

defineEmits<{
  'update:modelValue': [value: string]
}>()

const attrs = useAttrs()

const hasError = computed(() => Boolean(props.error))
const errorId = computed(() => `${props.id}-error`)

const shell = computed(() =>
  hasError.value
    ? 'bg-state-danger-fill outline-1 -outline-offset-1 outline-state-danger-outline focus:outline-2 focus:outline-offset-2 focus:outline-focus'
    : 'bg-gray-100 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:outline-offset-2 focus:outline-focus dark:bg-white/5 dark:outline-white/10'
)
</script>

<template>
  <div>
    <label :for="id" class="text-label text-ink block">
      {{ label }}
    </label>
    <div class="relative mt-2">
      <textarea
        :id="id"
        :value="modelValue"
        :placeholder="placeholder"
        :required="required"
        :disabled="disabled"
        :rows="rows ?? 3"
        :aria-invalid="hasError || undefined"
        :aria-describedby="hasError ? errorId : undefined"
        v-bind="attrs"
        class="block w-full rounded-md py-1.5 pl-3 text-base text-gray-900 placeholder:text-gray-400 sm:text-sm/6 dark:text-white dark:placeholder:text-stone-500"
        :class="[shell, hasError ? 'pr-10' : 'pr-3']"
        @input="
          $emit(
            'update:modelValue',
            ($event.target as HTMLTextAreaElement).value
          )
        "
      />
      <span
        v-if="hasError"
        data-testid="form-textarea-error-icon"
        class="text-state-danger-ink pointer-events-none absolute top-2 right-3 flex h-5 items-center"
      >
        <ExclamationCircleIcon class="size-5" aria-hidden="true" />
      </span>
    </div>
    <p v-if="hasError" :id="errorId" class="text-state-danger-ink mt-1 text-sm">
      {{ error }}
    </p>
    <p v-else-if="hint" class="text-ink-muted mt-3 text-sm/6">
      {{ hint }}
    </p>
  </div>
</template>
