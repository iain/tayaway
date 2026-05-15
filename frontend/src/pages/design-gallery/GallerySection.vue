<script setup lang="ts">
import { MoonIcon, SunIcon } from '@heroicons/vue/24/outline'
import { useDarkMode } from '@/composables/useDarkMode'

// One row in the design gallery. Renders its slot twice — once inside a `.light`
// island and once inside `.dark` — so a primitive's variants appear side by side
// in both modes. The `id` is the anchor target for the TOC; `scroll-mt-*` gives
// the landing position a touch of breathing room.
//
// Each mode column carries a small sun/moon glyph in its top-right corner.
// The label is glyph-only so the eyebrow tier inside the slot (token names,
// foundation sub-groups) reads as the dominant signal — typographic hierarchy
// goes to the content, not the wrapping frame.
//
// Screen readers hear only the column that matches the user's current global
// theme — the other column stays visually present for a sighted comparison
// but is marked aria-hidden so AT users aren't forced through every primitive
// twice.
defineProps<{
  id: string
  title: string
  description?: string
  motion?: string
}>()

const modes = ['light', 'dark'] as const

const { isDark } = useDarkMode()
</script>

<template>
  <section :id="id" class="scroll-mt-6">
    <div class="mb-heading">
      <h3 class="text-section-heading text-ink">{{ title }}</h3>
      <p v-if="description" class="text-ink-muted text-meta mt-1">
        {{ description }}
      </p>
    </div>

    <div class="grid gap-4 lg:grid-cols-2">
      <div
        v-for="mode in modes"
        :key="mode"
        :class="[
          mode,
          'bg-surface-page text-ink ring-ring-hairline relative rounded-lg p-6 ring-1',
        ]"
        :data-mode="mode"
        :aria-hidden="(mode === 'dark') !== isDark"
        :inert="(mode === 'dark') !== isDark"
      >
        <span class="sr-only">{{ mode }} mode</span>
        <component
          :is="mode === 'light' ? SunIcon : MoonIcon"
          class="text-ink-faint absolute top-6 right-6 size-4"
          aria-hidden="true"
        />
        <slot :mode="mode" />
      </div>
    </div>

    <p v-if="motion" class="text-ink-faint text-meta mt-3">
      <span class="font-medium">Motion —</span> {{ motion }}
    </p>
  </section>
</template>
