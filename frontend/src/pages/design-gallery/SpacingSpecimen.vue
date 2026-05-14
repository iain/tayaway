<script setup lang="ts">
// The three named spacing roles, shown as labelled gaps between demo blocks.
// The 4px Tailwind scale is the system; these tokens just name three values
// that live in enough places to deserve a single source of truth.
</script>

<template>
  <div class="space-y-6">
    <div>
      <p class="text-ink-faint mb-2 text-eyebrow">
        p-card · m-card — 24px
      </p>
      <div class="bg-surface ring-ring-hairline p-card rounded-md ring-1">
        <div class="border-line bg-surface-page rounded border border-dashed p-2">
          <p class="text-ink-muted text-meta text-center">Content</p>
        </div>
      </div>
      <p class="text-ink-muted text-meta mt-2">
        Card and page-header padding. The gap from the card edge to its
        contents.
      </p>
    </div>

    <div>
      <p class="text-ink-faint mb-2 text-eyebrow">
        mt-section — 32px
      </p>
      <div class="space-y-0">
        <div class="bg-surface ring-ring-hairline rounded-md px-3 py-2 ring-1">
          <p class="text-ink text-meta">First named region</p>
        </div>
        <div class="mt-section bg-surface ring-ring-hairline rounded-md px-3 py-2 ring-1">
          <p class="text-ink text-meta">Second named region</p>
        </div>
      </div>
      <p class="text-ink-muted text-meta mt-2">
        Gap between named regions on a page — typically the distance between
        two SectionHeading blocks.
      </p>
    </div>

    <div>
      <p class="text-ink-faint mb-2 text-eyebrow">
        mb-heading — 16px
      </p>
      <div>
        <h4 class="text-section-heading text-ink mb-heading">A region title</h4>
        <div class="bg-surface ring-ring-hairline rounded-md px-3 py-2 ring-1">
          <p class="text-ink text-meta">The region's body</p>
        </div>
      </div>
      <p class="text-ink-muted text-meta mt-2">
        Gap below a SectionHeading before its body content begins.
      </p>
    </div>

    <p class="text-ink-muted text-meta border-line border-t pt-4">
      The 4px Tailwind scale (<span class="font-mono">p-1</span>,
      <span class="font-mono">p-2</span>, …) is the system. Reach for a named
      role token only where one fits; never invent arbitrary values like
      <span class="font-mono">p-[13px]</span>.
    </p>
  </div>
</template>
