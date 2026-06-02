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
  type?: string
  placeholder?: string
  required?: boolean
  disabled?: boolean
  maxlength?: number
  autocomplete?: string
  prefix?: string
  error?: string
}>()

defineEmits<{
  'update:modelValue': [value: string]
}>()

const attrs = useAttrs()

const hasError = computed(() => Boolean(props.error))
const errorId = computed(() => `${props.id}-error`)

// Error state is carried by fill + icon + a 1px red edge — orthogonal to
// focus, which keeps its system-wide outset rose ring on top. The healthy
// branch keeps the hairline edge that swaps to the rose focus ring.
const wrapperShell = computed(() =>
  hasError.value
    ? 'bg-state-danger-fill outline-1 -outline-offset-1 outline-state-danger-outline focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-focus'
    : 'bg-surface-sunken outline-1 -outline-offset-1 outline-line focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-focus'
)

const inputShell = computed(() =>
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
    <div class="mt-2">
      <div
        v-if="prefix"
        class="relative flex items-center rounded-md pl-3"
        :class="wrapperShell"
      >
        <div class="text-ink-muted shrink-0 text-base select-none sm:text-sm/6">
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
          :aria-invalid="hasError || undefined"
          :aria-describedby="hasError ? errorId : undefined"
          v-bind="attrs"
          class="text-ink placeholder:text-ink-placeholder block min-w-0 grow bg-transparent py-1.5 pl-1 text-base focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 sm:text-sm/6"
          :class="hasError ? 'pr-10' : 'pr-3'"
          @input="
            $emit(
              'update:modelValue',
              ($event.target as HTMLInputElement).value
            )
          "
        />
        <span
          v-if="hasError"
          data-testid="form-input-error-icon"
          class="text-state-danger-ink pointer-events-none absolute inset-y-0 right-3 my-auto flex h-5 items-center"
        >
          <ExclamationCircleIcon class="size-5" aria-hidden="true" />
        </span>
      </div>
      <div v-else class="relative">
        <input
          :id="id"
          :type="type ?? 'text'"
          :value="modelValue"
          :placeholder="placeholder"
          :required="required"
          :disabled="disabled"
          :maxlength="maxlength"
          :autocomplete="autocomplete"
          :aria-invalid="hasError || undefined"
          :aria-describedby="hasError ? errorId : undefined"
          v-bind="attrs"
          class="text-ink placeholder:text-ink-placeholder block w-full rounded-md py-1.5 pl-3 text-base disabled:cursor-not-allowed disabled:opacity-50 sm:text-sm/6"
          :class="[inputShell, hasError ? 'pr-10' : 'pr-3']"
          @input="
            $emit(
              'update:modelValue',
              ($event.target as HTMLInputElement).value
            )
          "
        />
        <span
          v-if="hasError"
          data-testid="form-input-error-icon"
          class="text-state-danger-ink pointer-events-none absolute inset-y-0 right-3 my-auto flex h-5 items-center"
        >
          <ExclamationCircleIcon class="size-5" aria-hidden="true" />
        </span>
      </div>
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
