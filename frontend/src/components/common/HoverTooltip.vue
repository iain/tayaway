<script lang="ts">
// Hover-intent delay before the panel appears. Long enough that mousing across
// a list toward a control doesn't flash tooltips, short enough to feel snappy.
export const SHOW_DELAY_MS = 500
</script>

<script setup lang="ts">
import { nextTick, onBeforeUnmount, onMounted, ref } from 'vue'

// A passive metadata tooltip anchored to an element elsewhere in the DOM. The
// deliberate opposite of AnchoredPopover: it never takes focus, never receives
// pointer events, and is aria-hidden — consumers must expose the same
// information through an interactive, focusable path (e.g. an ActionMenu),
// which also covers touch devices; this component doesn't activate at all
// without a hover-capable pointer. The anchor is expected to outlive the
// tooltip (both unmount together in a row), so listeners bind once on mount.
const props = defineProps<{
  anchorEl: HTMLElement
}>()

const MARGIN = 8 // keep this much gap from every viewport edge
const GAP = 6 // gap between the anchor and the panel (leaves room for the arrow)

const open = ref(false)
const panelEl = ref<HTMLElement | null>(null)
const pos = ref({ top: 0, left: 0 })
const placement = ref<'above' | 'below'>('above')
const arrowLeft = ref(0)

let showTimer = 0

function reposition() {
  const el = panelEl.value
  if (!el) return

  const rect = props.anchorEl.getBoundingClientRect()
  const vw = window.innerWidth
  const vh = window.innerHeight
  const elW = el.offsetWidth
  const elH = el.offsetHeight

  // Horizontal: center over the anchor, then clamp inside the viewport.
  const anchorCenter = rect.left + rect.width / 2
  const left = Math.max(
    MARGIN,
    Math.min(anchorCenter - elW / 2, vw - elW - MARGIN)
  )

  // Vertical: prefer above the anchor; flip below when it would poke past the
  // top of the viewport. Clamp as a final safety net.
  const above = rect.top - GAP - elH
  if (above < MARGIN) {
    placement.value = 'below'
    pos.value = {
      top: Math.min(rect.bottom + GAP, vh - elH - MARGIN),
      left,
    }
  } else {
    placement.value = 'above'
    pos.value = { top: above, left }
  }

  // Keep the arrow pointing at the anchor's center even when the panel is
  // clamped, but never let it slide off the panel's rounded corners.
  arrowLeft.value = Math.max(12, Math.min(anchorCenter - left, elW - 12))
}

function onMouseEnter() {
  showTimer = window.setTimeout(async () => {
    open.value = true
    await nextTick()
    reposition()
  }, SHOW_DELAY_MS)
}

function hide() {
  clearTimeout(showTimer)
  open.value = false
}

onMounted(() => {
  if (!window.matchMedia('(hover: hover)').matches) return

  props.anchorEl.addEventListener('mouseenter', onMouseEnter)
  props.anchorEl.addEventListener('mouseleave', hide)
  // Capture phase catches scrolls in any ancestor; a stale tooltip drifting
  // away from its row is worse than simply dismissing it.
  window.addEventListener('scroll', hide, true)
})

onBeforeUnmount(() => {
  clearTimeout(showTimer)
  props.anchorEl.removeEventListener('mouseenter', onMouseEnter)
  props.anchorEl.removeEventListener('mouseleave', hide)
  window.removeEventListener('scroll', hide, true)
})
</script>

<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition duration-150 ease-out"
      enter-from-class="translate-y-0.5 opacity-0"
    >
      <div
        v-if="open"
        ref="panelEl"
        role="tooltip"
        aria-hidden="true"
        class="border-line bg-surface text-ink pointer-events-none fixed z-50 max-w-[calc(100vw-1rem)] rounded-lg border px-3 py-2 text-sm shadow-xl"
        :style="{ top: `${pos.top}px`, left: `${pos.left}px` }"
      >
        <slot />
        <span
          class="border-line bg-surface absolute size-2 -translate-x-1/2 rotate-45"
          :class="
            placement === 'above'
              ? '-bottom-1 border-r border-b'
              : '-top-1 border-t border-l'
          "
          :style="{ left: `${arrowLeft}px` }"
          aria-hidden="true"
        />
      </div>
    </Transition>
  </Teleport>
</template>
