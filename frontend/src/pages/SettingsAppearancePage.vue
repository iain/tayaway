<script setup lang="ts">
import { SwatchIcon } from '@heroicons/vue/24/outline'
import BaseCard from '@/components/common/BaseCard.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'
import { FormRadioGroup } from '@/components/form'
import { useDarkMode, type DarkModePreference } from '@/composables/useDarkMode'

const { preference, setPreference } = useDarkMode()

const options: { id: DarkModePreference; label: string }[] = [
  { id: 'light', label: 'Light' },
  { id: 'dark', label: 'Dark' },
  { id: 'system', label: 'Automatic' },
]

function onSelect(value: string): void {
  setPreference(value as DarkModePreference)
}
</script>

<template>
  <div>
    <SectionHeading :icon="SwatchIcon" title="Appearance" />
    <BaseCard padded>
      <FormRadioGroup
        name="theme"
        legend="Theme"
        description="Automatic follows your device's light or dark setting. This is
          saved on this device only — your other devices keep their own theme."
        :model-value="preference"
        :options="options"
        @update:model-value="onSelect"
      />
    </BaseCard>
  </div>
</template>
