<script setup lang="ts">
defineProps<{
  name: string
  legend: string
  description?: string
  modelValue: string
  options: { id: string; label: string }[]
  disabled?: boolean
}>()

defineEmits<{
  'update:modelValue': [value: string]
}>()
</script>

<template>
  <fieldset>
    <legend class="text-sm/6 font-semibold text-gray-900 dark:text-white">
      {{ legend }}
    </legend>
    <p
      v-if="description"
      class="mt-1 text-sm/6 text-gray-600 dark:text-stone-400"
    >
      {{ description }}
    </p>
    <div class="mt-6 space-y-6">
      <div
        v-for="option in options"
        :key="option.id"
        class="flex items-center gap-x-3"
      >
        <input
          :id="option.id"
          :name="name"
          type="radio"
          :checked="modelValue === option.id"
          :disabled="disabled"
          class="relative size-4 appearance-none rounded-full border border-gray-300 bg-gray-100 before:absolute before:inset-1 before:rounded-full before:bg-white not-checked:before:hidden checked:border-rose-500 checked:bg-rose-500 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-rose-500 disabled:border-gray-200 disabled:bg-gray-100 disabled:before:bg-gray-300 dark:border-white/10 dark:bg-white/5 dark:disabled:border-white/5 dark:disabled:bg-white/10 dark:disabled:before:bg-white/20 forced-colors:appearance-auto forced-colors:before:hidden"
          @change="$emit('update:modelValue', option.id)"
        />
        <label
          :for="option.id"
          class="block text-sm/6 font-medium text-gray-900 dark:text-white"
        >
          {{ option.label }}
        </label>
      </div>
    </div>
  </fieldset>
</template>
