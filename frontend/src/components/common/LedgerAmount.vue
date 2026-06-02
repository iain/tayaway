<script setup lang="ts">
import { computed } from 'vue'
import { useLocale } from '@/composables/useLocale'

// The system's signature amount treatment: tabular figures so columns line up,
// the currency symbol in `ink-faint` so it reads as context (not value), and
// an optional direction sign (+ inflow / − outflow) coloured to echo the
// dual-coding rule from the soft buttons. The digit colour intentionally
// inherits from the parent so a row can be dimmed by wrapping with
// `text-ink-muted` without forking this primitive.
//
// Set `direction` only when the +/− sign IS the directional signal — a
// column of transfers, a balance breakdown, anywhere the amount stands
// alone. Leave it off when the surrounding language already says "owes",
// "is owed", or "You owe": pairing a verb with a sign reads as a double
// negative ("owes −€15"). The verb wins; the amount stays neutral.
//
// Formatting goes through `Intl.NumberFormat` so thousands separators,
// decimal style, and currency placement track the active locale. The locale
// defaults to the app-wide `useLocale` value (which starts from the browser);
// pass `locale` explicitly for one-off overrides.
const props = defineProps<{
  amount: number
  direction?: 'in' | 'out'
  locale?: string
}>()

const { locale: appLocale } = useLocale()
const activeLocale = computed(() => props.locale ?? appLocale.value)

const parts = computed<Intl.NumberFormatPart[]>(() => {
  // Sign the value before formatting so `Intl` places the marker per locale
  // (some put it after the number; some put currency-then-sign-then-digits).
  const value =
    props.direction === 'out' ? -Math.abs(props.amount) : Math.abs(props.amount)
  const formatter = new Intl.NumberFormat(activeLocale.value, {
    style: 'currency',
    currency: 'EUR',
    signDisplay: props.direction ? 'always' : 'never',
  })
  return formatter.formatToParts(value)
})

function classForPart(type: Intl.NumberFormatPartTypes): string | undefined {
  if (type === 'currency' || type === 'literal') return 'text-ink-faint'
  if (type === 'plusSign') return 'text-btn-inflow-ink'
  if (type === 'minusSign') return 'text-btn-outflow-ink'
  return undefined
}

function valueForPart(part: Intl.NumberFormatPart): string {
  // Swap the locale's minus glyph (typically the ASCII hyphen) for the true
  // Unicode minus, which sits at the right optical weight for digits.
  if (part.type === 'minusSign') return '−'
  return part.value
}
</script>

<template>
  <span class="whitespace-nowrap tabular-nums">
    <span
      v-for="(part, i) in parts"
      :key="i"
      :class="classForPart(part.type)"
      >{{ valueForPart(part) }}</span
    >
  </span>
</template>
