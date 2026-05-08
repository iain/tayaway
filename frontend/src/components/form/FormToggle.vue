<script setup lang="ts">
defineProps<{
  id: string
  modelValue: boolean
  label?: string
  description?: string
  disabled?: boolean
  ariaLabel?: string
  name?: string
}>()

defineEmits<{
  'update:modelValue': [value: boolean]
}>()
</script>

<template>
  <div :class="['flex gap-3', { 'opacity-50': disabled }]">
    <div
      class="group relative inline-flex h-6 w-11 shrink-0 items-center rounded-full bg-gray-200 p-0.5 inset-ring inset-ring-gray-900/5 outline-offset-2 outline-rose-500 transition-colors duration-200 ease-in-out has-checked:bg-rose-500 has-focus-visible:outline-2 has-disabled:cursor-not-allowed dark:bg-white/5 dark:inset-ring-white/10 dark:outline-rose-500"
    >
      <span
        class="relative size-5 rounded-full bg-white shadow-xs ring-1 ring-gray-900/5 transition-transform duration-200 ease-in-out group-has-checked:translate-x-5"
      >
        <span
          class="absolute inset-0 flex size-full items-center justify-center opacity-100 transition-opacity duration-200 ease-in group-has-checked:opacity-0 group-has-checked:duration-100 group-has-checked:ease-out"
          aria-hidden="true"
        >
          <svg
            class="size-3 text-gray-400 dark:text-gray-600"
            fill="none"
            viewBox="0 0 12 12"
          >
            <path
              d="M4 8l2-2m0 0l2-2M6 6L4 4m2 2l2 2"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
            />
          </svg>
        </span>
        <span
          class="absolute inset-0 flex size-full items-center justify-center opacity-0 transition-opacity duration-100 ease-out group-has-checked:opacity-100 group-has-checked:duration-200 group-has-checked:ease-in"
          aria-hidden="true"
        >
          <svg
            class="size-3 text-rose-500"
            fill="currentColor"
            viewBox="0 0 12 12"
          >
            <path
              d="M3.707 5.293a1 1 0 00-1.414 1.414l1.414-1.414zM5 8l-.707.707a1 1 0 001.414 0L5 8zm4.707-3.293a1 1 0 00-1.414-1.414l1.414 1.414zm-7.414 2l2 2 1.414-1.414-2-2-1.414 1.414zm3.414 2l4-4-1.414-1.414-4 4 1.414 1.414z"
            />
          </svg>
        </span>
      </span>
      <input
        :id="id"
        type="checkbox"
        role="switch"
        :checked="modelValue"
        :disabled="disabled"
        :name="name"
        :aria-label="label ? undefined : ariaLabel"
        :aria-describedby="description ? `${id}-description` : undefined"
        class="absolute inset-0 size-full appearance-none focus:outline-hidden disabled:cursor-not-allowed"
        @change="
          $emit(
            'update:modelValue',
            ($event.target as HTMLInputElement).checked
          )
        "
      />
    </div>
    <div v-if="label || description" class="text-sm/6">
      <label
        v-if="label"
        :for="id"
        class="font-medium text-gray-900 dark:text-white"
      >
        {{ label }}
      </label>
      <p
        v-if="description"
        :id="`${id}-description`"
        class="text-gray-600 dark:text-stone-400"
      >
        {{ description }}
      </p>
    </div>
  </div>
</template>
