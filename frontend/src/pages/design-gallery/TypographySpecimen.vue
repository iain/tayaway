<script setup lang="ts">
// Six tiers, body-size by default. Each row pairs a specimen line set at the
// tier's utility with the token name and the values that utility bundles.
// Rendering both light and dark next to each other proves the ink/contrast
// pair as well as the type ramp itself.

interface Tier {
  name: string
  klass: string
  values: string
  example: string
}

const tiers: Tier[] = [
  {
    name: 'text-page-title',
    klass: 'text-page-title',
    values: '30px · 700 · 36px line · -2.5% tracking',
    example: 'Plan the Lisbon weekend',
  },
  {
    name: 'text-page-title-sm',
    klass: 'text-page-title-sm',
    values: '24px · 700 · 32px line · -2.5% tracking',
    example: 'Plan the Lisbon weekend',
  },
  {
    name: 'text-section-heading',
    klass: 'text-section-heading',
    values: '18px · 600 · 28px line',
    example: 'Dates the group has agreed on',
  },
  {
    name: 'text-body',
    klass: 'text-body',
    values: '16px · 400 · 24px line — default',
    example:
      'Body text is the default. Anything a user needs to read at a glance is body size; tighter tiers are deliberate choices, not reflexive defaults.',
  },
  {
    name: 'text-label',
    klass: 'text-label',
    values: '14px · 500 · 24px line',
    example: 'Form labels, button text, primary metadata',
  },
  {
    name: 'text-meta',
    klass: 'text-meta',
    values: '14px · 400 · 20px line',
    example: 'Last synced 8m ago',
  },
]
</script>

<template>
  <ul class="space-y-6">
    <li v-for="tier in tiers" :key="tier.name" class="space-y-1">
      <div class="flex flex-wrap items-baseline gap-x-3 gap-y-0.5">
        <span class="text-ink-faint text-meta font-mono">{{ tier.name }}</span>
        <span class="text-ink-muted text-meta">— {{ tier.values }}</span>
      </div>
      <p :class="['text-ink', tier.klass]">{{ tier.example }}</p>
    </li>
  </ul>
</template>
