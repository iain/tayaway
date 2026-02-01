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
    <legend class="text-sm/6 font-semibold text-white">{{ legend }}</legend>
    <p
      v-if="description"
      class="mt-1 text-sm/6 text-gray-400"
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
          class="relative size-4 appearance-none rounded-full border border-white/10 bg-white/5 before:absolute before:inset-1 before:rounded-full before:bg-white not-checked:before:hidden checked:border-indigo-500 checked:bg-indigo-500 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-500 disabled:border-white/5 disabled:bg-white/10 disabled:before:bg-white/20 forced-colors:appearance-auto forced-colors:before:hidden"
          @change="$emit('update:modelValue', option.id)"
        >
        <label
          :for="option.id"
          class="block text-sm/6 font-medium text-white"
        >
          {{ option.label }}
        </label>
      </div>
    </div>
  </fieldset>
</template>
