<script setup lang="ts">
import { computed } from 'vue'
import type { TOCItem } from '@/pages/design-gallery/types'
import { useActiveSection } from '@/pages/design-gallery/useActiveSection'

const props = defineProps<{
  items: TOCItem[]
}>()

const { activeId, scrollTo } = useActiveSection(props.items)

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
        <ul class="space-y-0.5">
          <li v-for="item in group.items" :key="item.id">
            <a
              :href="`#${item.id}`"
              :class="[
                'focus-visible:outline-focus -ml-2 block rounded-md px-2 py-1 transition-colors focus-visible:outline-2 focus-visible:outline-offset-2',
                activeId === item.id
                  ? 'bg-surface-sunken text-ink font-medium'
                  : 'text-ink-muted hover:bg-surface-sunken hover:text-ink',
              ]"
              @click="scrollTo($event, item.id)"
              >{{ item.label }}</a
            >
          </li>
        </ul>
      </li>
    </ol>
  </nav>
</template>
