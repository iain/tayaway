<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue'

// A non-modal popover anchored to an element elsewhere in the DOM. It owns the
// floating-layer concerns the chore popovers used to each reimplement by hand:
// viewport-clamped positioning that flips above the anchor when there's no room
// below, repositioning on scroll/resize, Escape-to-close, outside-click-close,
// and moving focus into the content on open (restoring it on close). The root
// keeps the `fixed z-50` hooks the chore e2e suite scopes its queries to.
const props = defineProps<{
  anchorEl: HTMLElement
  ariaLabel?: string
}>()

const emit = defineEmits<{
  close: []
}>()

const MARGIN = 8 // keep this much gap from every viewport edge
const GAP = 4 // gap between the anchor and the popover

const popoverEl = ref<HTMLElement | null>(null)
const pos = ref({ top: 0, left: 0 })
let previouslyFocused: HTMLElement | null = null

function reposition() {
  const el = popoverEl.value
  if (!el) return

  const rect = props.anchorEl.getBoundingClientRect()
  const vw = window.innerWidth
  const vh = window.innerHeight
  const elW = el.offsetWidth
  const elH = el.offsetHeight

  // Horizontal: align to the anchor's left edge, then clamp inside the viewport.
  const left = Math.max(MARGIN, Math.min(rect.left, vw - elW - MARGIN))

  // Vertical: prefer below the anchor; flip above when it would overflow the
  // bottom and there's more room above. Clamp as a final safety net.
  const below = rect.bottom + GAP
  const above = rect.top - GAP - elH
  const overflowsBelow = below + elH > vh - MARGIN
  let top = overflowsBelow && above > MARGIN ? above : below
  top = Math.max(MARGIN, Math.min(top, vh - elH - MARGIN))

  pos.value = { top, left }
}

// Scroll/resize can fire many times a frame; coalesce the layout read into one
// rAF tick so a held scroll doesn't thrash `getBoundingClientRect`.
let frame = 0
function scheduleReposition() {
  if (frame) return
  frame = requestAnimationFrame(() => {
    frame = 0
    reposition()
  })
}

function onKeydown(event: KeyboardEvent) {
  if (event.key === 'Escape') {
    event.stopPropagation()
    emit('close')
  }
}

function onPointerDown(event: MouseEvent) {
  if (popoverEl.value && !popoverEl.value.contains(event.target as Node)) {
    emit('close')
  }
}

onMounted(() => {
  previouslyFocused = document.activeElement as HTMLElement | null
  reposition()

  // Move focus to the first focusable control so keyboard users land inside the
  // popover rather than behind it on the trigger.
  const focusable = popoverEl.value?.querySelector<HTMLElement>(
    'input, textarea, select, button, [tabindex]:not([tabindex="-1"])'
  )
  focusable?.focus({ preventScroll: true })

  document.addEventListener('keydown', onKeydown)
  document.addEventListener('mousedown', onPointerDown)
  // Capture phase catches scrolls in any ancestor (the grid scrolls on the x).
  window.addEventListener('scroll', scheduleReposition, true)
  window.addEventListener('resize', scheduleReposition)
})

onBeforeUnmount(() => {
  document.removeEventListener('keydown', onKeydown)
  document.removeEventListener('mousedown', onPointerDown)
  window.removeEventListener('scroll', scheduleReposition, true)
  window.removeEventListener('resize', scheduleReposition)
  if (frame) cancelAnimationFrame(frame)

  // Return focus to the trigger (or wherever it was) when still in the document.
  const restoreTo = props.anchorEl?.isConnected
    ? props.anchorEl
    : previouslyFocused?.isConnected
      ? previouslyFocused
      : null
  restoreTo?.focus({ preventScroll: true })
})
</script>

<template>
  <div
    ref="popoverEl"
    role="dialog"
    :aria-label="ariaLabel"
    class="border-line bg-surface fixed z-50 w-64 max-w-[calc(100vw-1rem)] rounded-lg border p-3 shadow-xl"
    :style="{ top: `${pos.top}px`, left: `${pos.left}px` }"
  >
    <slot />
  </div>
</template>
