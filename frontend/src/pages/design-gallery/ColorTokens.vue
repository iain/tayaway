<script setup lang="ts">
// Every named color token in the system, grouped by role. Renders inside a
// GallerySection so the page-level light/dark islanding shows each token
// resolving to its mode-appropriate value side by side.
//
// The "swatch" is just a div with the token's background class — what you see
// is literally what the token produces in this mode. Tokens whose role is text
// or border get a small composed example instead of a fill block.

interface FillToken {
  name: string
  bg: string
  use: string
}

interface InkToken {
  name: string
  text: string
  use: string
}

interface RingToken {
  name: string
  ring: string
  use: string
}

const surfaces: FillToken[] = [
  {
    name: 'bg-surface',
    bg: 'bg-surface',
    use: 'Card and dialog surfaces',
  },
  {
    name: 'bg-surface-page',
    bg: 'bg-surface-page',
    use: 'Page background',
  },
  {
    name: 'bg-surface-sunken',
    bg: 'bg-surface-sunken',
    use: 'Sunken fills (inputs, secondary buttons)',
  },
  {
    name: 'bg-surface-action',
    bg: 'bg-surface-action',
    use: 'Action card variant — soft amber tint',
  },
  {
    name: 'bg-surface-urgent',
    bg: 'bg-surface-urgent',
    use: 'Urgent card variant — soft red tint',
  },
]

const inks: InkToken[] = [
  { name: 'text-ink', text: 'text-ink', use: 'Primary text' },
  {
    name: 'text-ink-muted',
    text: 'text-ink-muted',
    use: 'Subtitles, secondary metadata',
  },
  {
    name: 'text-ink-faint',
    text: 'text-ink-faint',
    use: 'Helper text, "last synced" labels',
  },
]

const lines: RingToken[] = [
  {
    name: 'ring-ring-hairline',
    ring: 'ring-1 ring-ring-hairline',
    use: 'Default card edge',
  },
  {
    name: 'ring-ring-hover',
    ring: 'ring-2 ring-ring-hover',
    use: 'Hover affordance on interactive cards',
  },
  {
    name: 'ring-ring-action',
    ring: 'ring-2 ring-ring-action',
    use: 'Action card edge',
  },
  {
    name: 'ring-ring-urgent',
    ring: 'ring-2 ring-ring-urgent',
    use: 'Urgent card edge',
  },
  {
    name: 'border-line',
    ring: 'border border-line',
    use: 'Dividers and hairline borders',
  },
]

const states: { name: string; fill: string; ink: string }[] = [
  {
    name: 'state-success',
    fill: 'bg-state-success-fill',
    ink: 'text-state-success-ink',
  },
  {
    name: 'state-danger',
    fill: 'bg-state-danger-fill',
    ink: 'text-state-danger-ink',
  },
  {
    name: 'state-warning',
    fill: 'bg-state-warning-fill',
    ink: 'text-state-warning-ink',
  },
  {
    name: 'state-pending',
    fill: 'bg-state-pending-fill',
    ink: 'text-state-pending-ink',
  },
  {
    name: 'state-info',
    fill: 'bg-state-info-fill',
    ink: 'text-state-info-ink',
  },
  {
    name: 'state-neutral',
    fill: 'bg-state-neutral-fill',
    ink: 'text-state-neutral-ink',
  },
]

const buttonSoft: { name: string; fill: string; ink: string }[] = [
  {
    name: 'btn-secondary',
    fill: 'bg-btn-secondary-fill',
    ink: 'text-btn-secondary-ink',
  },
  {
    name: 'btn-inflow',
    fill: 'bg-btn-inflow-fill',
    ink: 'text-btn-inflow-ink',
  },
  {
    name: 'btn-outflow',
    fill: 'bg-btn-outflow-fill',
    ink: 'text-btn-outflow-ink',
  },
]

const avatars: { name: string; fill: string; ink: string }[] = [
  {
    name: 'avatar-default',
    fill: 'bg-avatar-default-fill',
    ink: 'text-avatar-default-ink',
  },
  {
    name: 'avatar-pending',
    fill: 'bg-avatar-pending-fill',
    ink: 'text-avatar-pending-ink',
  },
]
</script>

<template>
  <div class="space-y-6">
    <div>
      <p class="text-ink-faint text-eyebrow mb-3">Surfaces</p>
      <ul class="space-y-2">
        <li
          v-for="token in surfaces"
          :key="token.name"
          class="flex items-center gap-3"
        >
          <div
            class="ring-ring-hairline size-10 shrink-0 rounded-md ring-1"
            :class="token.bg"
          />
          <div class="min-w-0">
            <p class="text-ink text-label font-mono">{{ token.name }}</p>
            <p class="text-ink-muted text-meta">{{ token.use }}</p>
          </div>
        </li>
      </ul>
    </div>

    <div>
      <p class="text-ink-faint text-eyebrow mb-3">Ink</p>
      <ul class="space-y-2">
        <li
          v-for="token in inks"
          :key="token.name"
          class="flex items-center gap-3"
        >
          <div
            class="bg-surface ring-ring-hairline flex size-10 shrink-0 items-center justify-center rounded-md ring-1"
          >
            <span class="text-base font-semibold" :class="token.text">Aa</span>
          </div>
          <div class="min-w-0">
            <p class="text-ink text-label font-mono">{{ token.name }}</p>
            <p class="text-ink-muted text-meta">{{ token.use }}</p>
          </div>
        </li>
      </ul>
    </div>

    <div>
      <p class="text-ink-faint text-eyebrow mb-3">Lines &amp; rings</p>
      <ul class="space-y-2">
        <li
          v-for="token in lines"
          :key="token.name"
          class="flex items-center gap-3"
        >
          <div
            class="bg-surface size-10 shrink-0 rounded-md"
            :class="token.ring"
          />
          <div class="min-w-0">
            <p class="text-ink text-label font-mono">{{ token.name }}</p>
            <p class="text-ink-muted text-meta">{{ token.use }}</p>
          </div>
        </li>
      </ul>
    </div>

    <div>
      <p class="text-ink-faint text-eyebrow mb-3">Focus</p>
      <p class="text-ink-muted text-meta mb-2">
        One ring for every interactive element — buttons, inputs, cards, modals.
        Tab into anything to see it live.
      </p>
      <div class="flex items-center gap-3">
        <button
          type="button"
          class="bg-surface ring-ring-hairline focus-visible:outline-focus rounded-md px-3 py-1.5 text-sm font-semibold ring-1 focus-visible:outline-2 focus-visible:outline-offset-2"
        >
          Tab to me
        </button>
        <p class="text-ink-muted text-meta font-mono">
          focus-visible:outline-focus
        </p>
      </div>
    </div>

    <div>
      <p class="text-ink-faint text-eyebrow mb-3">State (fill + ink)</p>
      <ul class="space-y-2">
        <li
          v-for="token in states"
          :key="token.name"
          class="flex items-center gap-3"
        >
          <span
            class="inline-flex h-10 shrink-0 items-center rounded-full px-3 text-xs font-medium"
            :class="[token.fill, token.ink]"
            >{{ token.name }}</span
          >
          <p class="text-ink text-label font-mono">
            bg-{{ token.name }}-fill · text-{{ token.name }}-ink
          </p>
        </li>
      </ul>
    </div>

    <div>
      <p class="text-ink-faint text-eyebrow mb-3">Soft buttons</p>
      <ul class="space-y-2">
        <li
          v-for="token in buttonSoft"
          :key="token.name"
          class="flex items-center gap-3"
        >
          <span
            class="inline-flex h-10 shrink-0 items-center rounded-md px-3 text-sm font-semibold"
            :class="[token.fill, token.ink]"
            >{{ token.name }}</span
          >
          <p class="text-ink text-label font-mono">
            bg-{{ token.name }}-fill · text-{{ token.name }}-ink
          </p>
        </li>
      </ul>
    </div>

    <div>
      <p class="text-ink-faint text-eyebrow mb-3">Avatars</p>
      <ul class="space-y-2">
        <li
          v-for="token in avatars"
          :key="token.name"
          class="flex items-center gap-3"
        >
          <span
            class="inline-flex size-10 shrink-0 items-center justify-center rounded-full text-sm font-semibold"
            :class="[token.fill, token.ink]"
            >IK</span
          >
          <p class="text-ink text-label font-mono">
            bg-{{ token.name }}-fill · text-{{ token.name }}-ink
          </p>
        </li>
      </ul>
    </div>

    <div>
      <p class="text-ink-faint text-eyebrow mb-3">Nav</p>
      <div
        class="bg-nav text-nav-text flex items-center gap-3 rounded-md px-4 py-3"
      >
        <span class="text-sm font-bold">Workspace</span>
        <span class="text-nav-text-muted text-sm">Events</span>
        <span class="bg-nav-active rounded px-2 py-0.5 text-sm font-medium">
          Active
        </span>
      </div>
      <p class="text-ink-muted text-meta mt-2">
        <span class="font-mono">bg-nav</span> ·
        <span class="font-mono">bg-nav-active</span> ·
        <span class="font-mono">text-nav-text</span> — only used on the sticky
        top nav and its descendants.
      </p>
    </div>
  </div>
</template>
