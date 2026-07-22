<script setup lang="ts">
import { computed } from 'vue'
import FormSelect from '@/components/form/FormSelect.vue'

// A timezone picker over the full IANA list, with a leading "auto" option
// (value ""). Used for the event zone (auto = derive from location) and the
// user's display zone (auto = follow this device). The effective zone is shown
// as a hint while "auto" is selected, so the implicit choice stays visible.
//
// `autoLabel: null` drops the auto option for the zones that are always
// explicit — a workspace's own zone is what everything else falls back to,
// so there is nothing behind it to defer to.
const props = defineProps<{
  id: string
  label: string
  modelValue: string // "" = auto/default
  autoLabel: string | null
  disabled?: boolean
  effectiveZone?: string | null
}>()

const emit = defineEmits<{ 'update:modelValue': [value: string] }>()

function supportedZones(): string[] {
  const intl = Intl as unknown as {
    supportedValuesOf?: (key: 'timeZone') => string[]
  }
  return intl.supportedValuesOf ? intl.supportedValuesOf('timeZone') : []
}

const options = computed(() => [
  ...(props.autoLabel === null ? [] : [{ value: '', label: props.autoLabel }]),
  ...supportedZones().map((z) => ({ value: z, label: z })),
])
</script>

<template>
  <div>
    <FormSelect
      :id="id"
      :label="label"
      :model-value="modelValue"
      :options="options"
      :disabled="disabled"
      @update:model-value="emit('update:modelValue', $event)"
    />
    <p
      v-if="modelValue === '' && effectiveZone"
      class="text-ink-muted text-meta mt-1"
    >
      Times shown in {{ effectiveZone }}
    </p>
  </div>
</template>
