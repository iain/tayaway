<script setup lang="ts">
import { SwatchIcon, LanguageIcon } from '@heroicons/vue/24/outline'
import BaseCard from '@/components/common/BaseCard.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'
import { FormRadioGroup } from '@/components/form'
import { useDarkMode, type DarkModePreference } from '@/composables/useDarkMode'
import { useLocale, browserLocale } from '@/composables/useLocale'
import { formatDateShort } from '@/utils/date'
import { formatAmount } from '@/utils/format'

const { preference, setPreference } = useDarkMode()

const options: { id: DarkModePreference; label: string }[] = [
  { id: 'light', label: 'Light' },
  { id: 'dark', label: 'Dark' },
  { id: 'system', label: 'Automatic' },
]

function onSelect(value: string): void {
  setPreference(value as DarkModePreference)
}

const { preference: localePreference, setLocale, clearLocale } = useLocale()

// A date with the day past 12 plus an amount, so each option's sample shows
// its day/month order and number style at a glance.
function formatSample(locale: string): string {
  return `${formatDateShort('2026-01-31', locale)} · ${formatAmount(1234.56, locale)}`
}

const localeOptions: { id: string; name: string }[] = [
  { id: 'auto', name: 'Automatic' },
  { id: 'en-US', name: 'English (US)' },
  { id: 'en-GB', name: 'English (UK)' },
  { id: 'en-NL', name: 'English (Netherlands)' },
  { id: 'nl-NL', name: 'Nederlands' },
]

const formatOptions = localeOptions.map(({ id, name }) => ({
  id,
  label: `${name} · ${formatSample(id === 'auto' ? browserLocale : id)}`,
}))

function onSelectFormat(value: string): void {
  if (value === 'auto') {
    clearLocale()
  } else {
    setLocale(value)
  }
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

    <div class="mt-8">
      <SectionHeading :icon="LanguageIcon" title="Formats" />
      <BaseCard padded>
        <FormRadioGroup
          name="locale"
          legend="Date and number format"
          description="How dates and amounts are written throughout the app.
            Automatic follows your browser's language. Saved on this device
            only — your other devices keep their own format."
          :model-value="localePreference ?? 'auto'"
          :options="formatOptions"
          @update:model-value="onSelectFormat"
        />
      </BaseCard>
    </div>
  </div>
</template>
