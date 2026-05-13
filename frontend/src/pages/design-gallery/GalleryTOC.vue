<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import type { TOCItem } from '@/pages/design-gallery/types'

const props = defineProps<{
  items: TOCItem[]
}>()

const activeId = ref<string | null>(null)
let observer: IntersectionObserver | null = null

// Group items in display order, preserving first-seen group sequence so the
// TOC matches the page top-to-bottom rather than alphabetising group names.
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
  // Highlight whichever section is currently mid-viewport. The asymmetric
  // root margin biases activation toward the upper third so a section
  // becomes active as it crosses into reading position, not when it's already
  // half off-screen at the bottom.
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

onBeforeUnmount(() => {
  observer?.disconnect()
})

function handleClick(event: MouseEvent, id: string): void {
  // Smooth-scroll the anchor; respect prefers-reduced-motion by deferring to
  // the browser's native jump for users that have asked for less movement.
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
  <nav aria-label="Design gallery sections" class="text-meta">
    <ol class="space-y-6">
      <li v-for="group in grouped" :key="group.group">
        <p
          class="text-ink-faint mb-2 text-xs font-semibold tracking-wide uppercase"
        >
          {{ group.group }}
        </p>
        <ul class="space-y-1">
          <li v-for="item in group.items" :key="item.id">
            <a
              :href="`#${item.id}`"
              :class="[
                'focus-visible:outline-focus block rounded-sm border-l-2 py-0.5 pl-3 transition-colors focus-visible:outline-2 focus-visible:outline-offset-2',
                activeId === item.id
                  ? 'border-rose-500 text-ink font-medium'
                  : 'border-transparent text-ink-muted hover:text-ink hover:border-line',
              ]"
              @click="handleClick($event, item.id)"
              >{{ item.label }}</a
            >
          </li>
        </ul>
      </li>
    </ol>
  </nav>
</template>
