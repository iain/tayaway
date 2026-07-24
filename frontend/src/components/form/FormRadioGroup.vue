<script setup lang="ts">
import { useId } from 'vue'

const props = defineProps<{
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

const uid = useId()
const descriptionId = `${uid}-description`

// Option ids namespace under the group's name: two groups on one page can
// legitimately share option ids ("light" in one, "light" in another), and a
// duplicate DOM id silently breaks label association for both.
function inputId(optionId: string): string {
  return `${props.name}-${optionId}`
}
</script>

<template>
  <fieldset :aria-describedby="description ? descriptionId : undefined">
    <legend class="text-ink text-sm/6 font-semibold">
      {{ legend }}
    </legend>
    <p
      v-if="description"
      :id="descriptionId"
      class="text-ink-muted mt-1 text-sm/6"
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
          :id="inputId(option.id)"
          :name="name"
          type="radio"
          :value="option.id"
          :checked="modelValue === option.id"
          :disabled="disabled"
          class="bg-surface-sunken border-line focus-visible:outline-focus relative size-4 appearance-none rounded-full border before:absolute before:inset-1 before:rounded-full before:bg-white not-checked:before:hidden after:absolute after:inset-x-0 after:-inset-y-2 after:content-[''] checked:border-rose-500 checked:bg-rose-500 focus-visible:outline-2 focus-visible:outline-offset-2 disabled:cursor-not-allowed disabled:opacity-50 forced-colors:appearance-auto forced-colors:before:hidden"
          @change="$emit('update:modelValue', option.id)"
        />
        <!-- Radio and label each bleed 8px above and below, and the label
             reaches back across the gap between them, so the row answers to a
             ~40px touch without the layout growing — the same trick the
             navbar's workspace switcher uses. The label's bleed stops at the
             radio's edge: overlapping it would leave the radio unclickable. -->
        <label
          :for="inputId(option.id)"
          class="text-label text-ink relative block after:absolute after:-inset-y-2 after:right-0 after:-left-3 after:content-['']"
        >
          {{ option.label }}
        </label>
      </div>
    </div>
  </fieldset>
</template>
