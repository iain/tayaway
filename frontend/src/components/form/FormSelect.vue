<script setup lang="ts">
import { computed, useAttrs } from 'vue'
import { ChevronDownIcon } from '@heroicons/vue/16/solid'
import { ExclamationCircleIcon } from '@heroicons/vue/20/solid'

defineOptions({
  inheritAttrs: false,
})

const props = defineProps<{
  id: string
  label: string
  modelValue: string
  options: { value: string; label: string; disabled?: boolean }[]
  required?: boolean
  disabled?: boolean
  autocomplete?: string
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
    : 'bg-surface-sunken outline-1 -outline-offset-1 outline-line focus:outline-2 focus:outline-offset-2 focus:outline-focus'
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
        v-bind="attrs"
        class="text-ink *:bg-surface col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pl-3 text-base disabled:cursor-not-allowed disabled:opacity-50 sm:text-sm/6"
        :class="[shell, hasError ? 'pr-16' : 'pr-8']"
        @change="
          $emit('update:modelValue', ($event.target as HTMLSelectElement).value)
        "
      >
        <option
          v-for="option in options"
          :key="option.value"
          :value="option.value"
          :disabled="option.disabled"
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
        class="text-ink-muted pointer-events-none col-start-1 row-start-1 mr-2 size-5 self-center justify-self-end sm:size-4"
        aria-hidden="true"
      />
    </div>
    <p
      v-if="hasError"
      :id="errorId"
      class="text-state-danger-ink text-meta mt-1"
    >
      {{ error }}
    </p>
  </div>
</template>
