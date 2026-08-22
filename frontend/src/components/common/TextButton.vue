<script setup lang="ts">
import { computed } from 'vue'

const props = withDefaults(
  defineProps<{
    variant?: 'primary' | 'secondary' | 'danger'
    disabled?: boolean
    href?: string
    // Set when the button sits inside a run of text rather than on its own
    // line. See `hitArea` below.
    inline?: boolean
  }>(),
  { variant: 'primary', href: undefined, inline: false }
)

defineEmits<{
  click: []
}>()

const variantClasses: Record<string, string> = {
  // Primary uses Navigator Cyan Deep (cyan-700) so the underlined link clears
  // WCAG AA 4.5:1 on both `surface` and `surface-page` — cyan-600 (the brand
  // canonical) fell to ~3.3:1 on the page surface. Dark mode keeps cyan-400.
  primary:
    'text-cyan-700 underline hover:text-cyan-800 dark:text-cyan-400 dark:hover:text-cyan-300',
  // secondary lifted to ink-muted so it clears WCAG AA 4.5:1 on both surface
  // and surface-page — text-gray-500 fell short on the page surface.
  secondary: 'text-ink-muted hover:text-ink',
  danger:
    'text-red-600 hover:text-red-500 dark:text-red-400 dark:hover:text-red-300',
}

// A text button paints at ~20px tall, under the 24px WCAG 2.5.8 floor and well
// under a comfortable thumb. The transparent `after` bleed buys the hit area
// vertically without the layout growing around it (see DESIGN.md, Hit Areas);
// horizontal stays `inset-x-0` so neighbouring controls keep their own clicks.
//
// An `inline` button is exempt: 2.5.8 does not apply to targets constrained by
// the line-height of the text around them, and bleeding 8px into the lines
// above and below would only overlap the neighbouring rows' own targets.
const hitArea =
  "after:absolute after:inset-x-0 after:-inset-y-2 after:content-['']"

const variantClass = computed(() => variantClasses[props.variant])
const tag = computed(() => (props.href ? 'a' : 'button'))
</script>

<template>
  <component
    :is="tag"
    v-bind="
      href
        ? { href, target: '_blank', rel: 'noopener' }
        : { type: 'button', disabled }
    "
    class="focus-visible:outline-focus relative inline-flex cursor-pointer items-center gap-2 text-sm transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
    :class="[variantClass, inline ? '' : hitArea]"
    @click="$emit('click')"
  >
    <slot />
  </component>
</template>
