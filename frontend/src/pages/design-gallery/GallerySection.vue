<script setup lang="ts">
// One row in the design gallery. Renders its slot twice — once inside a `.light`
// island and once inside `.dark` — so a primitive's variants appear side by side
// in both modes. The `id` is the anchor target for the TOC; `scroll-mt-*` gives
// the landing position a touch of breathing room.
defineProps<{
  id: string
  title: string
  description?: string
  motion?: string
}>()

const modes = ['light', 'dark'] as const
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
          'bg-surface-page ring-ring-hairline rounded-lg p-6 ring-1',
        ]"
        :data-mode="mode"
      >
        <p
          class="text-ink-faint mb-4 text-xs font-semibold tracking-wide uppercase"
        >
          {{ mode }}
        </p>
        <slot :mode="mode" />
      </div>
    </div>

    <p v-if="motion" class="text-ink-faint text-meta mt-3">
      <span class="font-medium">Motion —</span> {{ motion }}
    </p>
  </section>
</template>
