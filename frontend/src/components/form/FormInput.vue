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
// branch keeps the gray edge that swaps to the rose focus ring.
const wrapperShell = computed(() =>
  hasError.value
    ? 'bg-state-danger-fill outline-1 -outline-offset-1 outline-state-danger-outline focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-focus'
    : 'bg-gray-100 outline-1 -outline-offset-1 outline-gray-300 focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-focus dark:bg-white/5 dark:outline-white/10'
)

const inputShell = computed(() =>
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
    <div class="mt-2">
      <div
        v-if="prefix"
        class="relative flex items-center rounded-md pl-3"
        :class="wrapperShell"
      >
        <div
          class="shrink-0 text-base text-gray-500 select-none sm:text-sm/6 dark:text-stone-400"
        >
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
          class="block min-w-0 grow bg-transparent py-1.5 pl-1 text-base text-gray-900 placeholder:text-gray-400 focus:outline-none sm:text-sm/6 dark:text-white dark:placeholder:text-stone-500"
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
          class="block w-full rounded-md py-1.5 pl-3 text-base text-gray-900 placeholder:text-gray-400 sm:text-sm/6 dark:text-white dark:placeholder:text-stone-500"
          :class="[inputShell, hasError ? 'pr-10' : 'pr-3']"
          @input="
            $emit('update:modelValue', ($event.target as HTMLInputElement).value)
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
    <p v-if="hasError" :id="errorId" class="text-state-danger-ink mt-1 text-sm">
      {{ error }}
    </p>
  </div>
</template>
