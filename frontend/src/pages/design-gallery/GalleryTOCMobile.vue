<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import type { TOCItem } from '@/pages/design-gallery/types'

const props = defineProps<{ items: TOCItem[] }>()

const activeId = ref<string | null>(null)
const scroller = ref<HTMLElement | null>(null)
let observer: IntersectionObserver | null = null

// Bucket items by group while preserving the order they appear in. Groups
// render as adjacent chip clusters separated by a vertical hairline, so the
// rail's grouping becomes visible on the chip row too.
const grouped = computed(() => {
  const out: { group: string; items: TOCItem[] }[] = []
  for (const item of props.items) {
    const bucket = out.find((g) => g.group === item.group)
    if (bucket) {
      bucket.items.push(item)
    } else {
      out.push({ group: item.group, items: [item] })
    }
  }
  return out
})

onMounted(() => {
  // Same activation logic as the desktop rail — biased toward the upper third
  // so a chip becomes active as its section crosses into reading position.
  observer = new IntersectionObserver(
    (entries) => {
      const visible = entries
        .filter((e) => e.isIntersecting)
        .sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top)
      if (visible[0]) {
        activeId.value = visible[0].target.id
      }
    },
    { rootMargin: '-20% 0px -70% 0px', threshold: 0 }
  )
  for (const item of props.items) {
    const el = document.getElementById(item.id)
    if (el) observer.observe(el)
  }
})

// Keep the active chip horizontally in view as the reader scrolls past
// sections. Without this the active state silently drifts off-screen.
watch(activeId, (id) => {
  if (!id || !scroller.value) return
  const chip = scroller.value.querySelector<HTMLElement>(`[data-chip="${id}"]`)
  if (!chip) return
  const containerRect = scroller.value.getBoundingClientRect()
  const chipRect = chip.getBoundingClientRect()
  if (chipRect.left < containerRect.left || chipRect.right > containerRect.right) {
    chip.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'center' })
  }
})

onBeforeUnmount(() => observer?.disconnect())

function handleClick(event: MouseEvent, id: string): void {
  const prefersReducedMotion = window.matchMedia(
    '(prefers-reduced-motion: reduce)'
  ).matches
  const target = document.getElementById(id)
  if (!target) return
  event.preventDefault()
  target.scrollIntoView({
    behavior: prefersReducedMotion ? 'auto' : 'smooth',
    block: 'start',
  })
  history.replaceState(null, '', `#${id}`)
  activeId.value = id
}
</script>

<template>
  <nav
    aria-label="Design gallery sections"
    class="border-line bg-surface-page sticky top-0 z-20 -mx-4 border-b sm:-mx-6 lg:hidden"
  >
    <ol
      ref="scroller"
      class="scroller flex gap-1 overflow-x-auto px-4 py-2 sm:px-6"
    >
      <template v-for="(group, gi) in grouped" :key="group.group">
        <li
          v-if="gi > 0"
          aria-hidden="true"
          class="bg-line mx-1 my-1.5 w-px shrink-0 self-stretch"
        />
        <li v-for="item in group.items" :key="item.id" class="shrink-0">
          <a
            :href="`#${item.id}`"
            :data-chip="item.id"
            :class="[
              'focus-visible:outline-focus inline-flex items-center rounded-full px-3 py-1.5 text-sm transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 min-h-[36px]',
              activeId === item.id
                ? 'bg-surface-sunken text-ink font-medium'
                : 'text-ink-muted hover:bg-surface-sunken hover:text-ink',
            ]"
            @click="handleClick($event, item.id)"
            >{{ item.label }}</a
          >
        </li>
      </template>
    </ol>
  </nav>
</template>

<style scoped>
/* Fade the scroll edges so it's clear there's more content offscreen. The
   mask starts opaque at 1rem from each edge — same distance as the ol's
   horizontal padding — so the first/last chips aren't dimmed, only the
   padding area is. */
.scroller {
  mask-image: linear-gradient(
    to right,
    transparent,
    black 1rem,
    black calc(100% - 1rem),
    transparent
  );
}
</style>
