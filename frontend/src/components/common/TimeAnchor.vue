<script setup lang="ts">
import { computed } from 'vue'
import { useLocale } from '@/composables/useLocale'
import { useRelativeTime } from '@/composables/useRelativeTime'
import { formatDateTime } from '@/utils/date'

// The Tayaway time voice in one primitive. The slot carries the verb in the
// right tense ("Sent", "Last synced", "Paid by Daisy", "Expires"); the
// component renders the compact relative time after it. The verb's tense
// chooses how the time reads ("ago" for past, "in" for future); the
// component doesn't try to be clever about that — picking the verb is the
// consumer's call.
//
// Accessibility:
//   - Renders a native `<time datetime="…">` so parsers and assistive tech
//     can read the absolute ISO timestamp.
//   - The whole element carries a `title` with the formatted absolute
//     date+time, so a sighted user hovering the row sees "May 13, 09:00"
//     and doesn't have to mental-math "3h ago" backwards from the clock.
//   - The visible text (verb + compact relative) is the accessible name
//     for screen readers by default.
//
// A `title` passed by the consumer overrides the auto-generated one — escape
// hatch for the rare case where a different absolute label fits better.
const props = defineProps<{
  at: string
  title?: string
}>()

defineOptions({ inheritAttrs: false })

const { locale } = useLocale()
const relative = useRelativeTime(() => props.at)
const tooltip = computed(
  () => props.title ?? formatDateTime(props.at, locale.value)
)
</script>

<template>
  <span :title="tooltip" v-bind="$attrs">
    <template v-if="$slots.default"><slot />&nbsp;</template
    ><time :datetime="at">{{ relative }}</time>
  </span>
</template>
