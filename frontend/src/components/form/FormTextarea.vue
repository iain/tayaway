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
  maxlength?: number
  showCount?: boolean
}>()

defineEmits<{
  'update:modelValue': [value: string]
}>()

const attrs = useAttrs()

const hasError = computed(() => Boolean(props.error))
const errorId = computed(() => `${props.id}-error`)

// The counter is a soft nudge as free text approaches the (hard) maxlength cap:
// muted normally, amber past 90%, danger once it hits the limit.
const showCounter = computed(() => Boolean(props.showCount && props.maxlength))
const countColor = computed(() => {
  const max = props.maxlength ?? 0
  const length = props.modelValue.length
  if (length >= max) {
    return 'text-state-danger-ink'
  } else if (length >= max * 0.9) {
    return 'text-state-warning-ink'
  } else {
    return 'text-ink-muted'
  }
})

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
    <div class="relative mt-2">
      <textarea
        :id="id"
        :value="modelValue"
        :placeholder="placeholder"
        :required="required"
        :disabled="disabled"
        :rows="rows ?? 3"
        :maxlength="maxlength"
        :aria-invalid="hasError || undefined"
        :aria-describedby="hasError ? errorId : undefined"
        v-bind="attrs"
        class="text-ink placeholder:text-ink-placeholder block w-full rounded-md py-1.5 pl-3 text-base disabled:cursor-not-allowed disabled:opacity-50 sm:text-sm/6"
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
    <p
      v-if="hasError"
      :id="errorId"
      class="text-state-danger-ink text-meta mt-1"
    >
      {{ error }}
    </p>
    <p v-else-if="hint" class="text-ink-muted text-meta mt-3">
      {{ hint }}
    </p>
    <div v-if="showCounter" class="mt-1 text-right">
      <span
        data-testid="form-textarea-count"
        class="text-meta tabular-nums"
        :class="countColor"
      >
        {{ modelValue.length }}/{{ maxlength }}
      </span>
    </div>
  </div>
</template>
