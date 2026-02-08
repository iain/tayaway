<script setup lang="ts">
defineProps<{
  id: string
  label: string
  description?: string
  modelValue: boolean
  disabled?: boolean
}>()

defineEmits<{
  'update:modelValue': [value: boolean]
}>()
</script>

<template>
  <div class="flex gap-3">
    <div class="flex h-6 shrink-0 items-center">
      <div class="group grid size-4 grid-cols-1">
        <input
          :id="id"
          type="checkbox"
          :checked="modelValue"
          :disabled="disabled"
          :aria-describedby="description ? `${id}-description` : undefined"
          class="col-start-1 row-start-1 appearance-none rounded-sm border border-white/10 bg-white/5 checked:border-rose-500 checked:bg-rose-500 indeterminate:border-rose-500 indeterminate:bg-rose-500 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-rose-500 disabled:border-white/5 disabled:bg-white/10 disabled:checked:bg-white/10 forced-colors:appearance-auto"
          @change="$emit('update:modelValue', ($event.target as HTMLInputElement).checked)"
        >
        <svg
          class="pointer-events-none col-start-1 row-start-1 size-3.5 self-center justify-self-center stroke-white group-has-disabled:stroke-white/25"
          viewBox="0 0 14 14"
          fill="none"
        >
          <path
            class="opacity-0 group-has-checked:opacity-100"
            d="M3 8L6 11L11 3.5"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
        </svg>
      </div>
    </div>
    <div class="text-sm/6">
      <label
        :for="id"
        class="font-medium text-white"
      >
        {{ label }}
      </label>
      <p
        v-if="description"
        :id="`${id}-description`"
        class="text-gray-400"
      >
        {{ description }}
      </p>
    </div>
  </div>
</template>
