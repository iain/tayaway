<script setup lang="ts">
import { computed } from 'vue'
import { ChevronDownIcon } from '@heroicons/vue/16/solid'
import { ExclamationCircleIcon } from '@heroicons/vue/20/solid'

const props = defineProps<{
  id: string
  label: string
  modelValue: string
  options: { value: string; label: string }[]
  required?: boolean
  disabled?: boolean
  autocomplete?: string
  error?: string
}>()

defineEmits<{
  'update:modelValue': [value: string]
}>()

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
    <div class="mt-2 grid grid-cols-1">
      <select
        :id="id"
        :value="modelValue"
        :required="required"
        :disabled="disabled"
        :autocomplete="autocomplete"
        :aria-invalid="hasError || undefined"
        :aria-describedby="hasError ? errorId : undefined"
        class="col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pl-3 text-base text-gray-900 *:bg-white sm:text-sm/6 dark:text-white dark:*:bg-stone-800"
        :class="[shell, hasError ? 'pr-16' : 'pr-8']"
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
      <span
        v-if="hasError"
        data-testid="form-select-error-icon"
        class="text-state-danger-ink pointer-events-none col-start-1 row-start-1 mr-8 flex items-center self-center justify-self-end"
      >
        <ExclamationCircleIcon class="size-5 sm:size-4" aria-hidden="true" />
      </span>
      <ChevronDownIcon
        class="pointer-events-none col-start-1 row-start-1 mr-2 size-5 self-center justify-self-end text-gray-400 sm:size-4"
        aria-hidden="true"
      />
    </div>
    <p v-if="hasError" :id="errorId" class="text-state-danger-ink mt-1 text-sm">
      {{ error }}
    </p>
  </div>
</template>
