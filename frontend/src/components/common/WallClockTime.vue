<script setup lang="ts">
import { computed } from 'vue'
import { storeToRefs } from 'pinia'
import { useAuthStore } from '@/stores/auth'
import {
  wallClockToEpoch,
  deviceTimezone,
  formatTimeInZone,
  formatZoneAbbrev,
} from '@/utils/timezone'

// A wall-clock time that happens in a specific zone — a chore time, an event
// time — as opposed to an absolute instant (use TimeAnchor for those). Renders
// short in the event's zone and always carries a tooltip with the full picture,
// so the visible label can stay implicit but the exact moment is one hover away.
const props = withDefaults(
  defineProps<{
    // The event's IANA zone the time is read in.
    zone: string
    // "HH:MM", or null for an all-day (timeless) chore.
    time: string | null
    // The civil date ("YYYY-MM-DD") the time falls on. Optional: without it the
    // time is a recurring wall-clock (e.g. a roster column header) and the
    // tooltip can't show a your-time equivalent for a specific day.
    date?: string
    // What to show when there is no time.
    allDayLabel?: string
  }>(),
  { date: undefined, allDayLabel: 'All day' }
)

const { user } = storeToRefs(useAuthStore())

// The viewer's display zone: their explicit preference, else this device.
const viewerZone = computed(() => user.value?.timezone ?? deviceTimezone())

const instant = computed(() =>
  props.date != null && props.time != null
    ? wallClockToEpoch(props.date, props.time, props.zone)
    : null
)

const label = computed(() =>
  props.time == null ? props.allDayLabel : props.time
)

const tooltip = computed(() => {
  if (props.time == null) return `All day · ${props.zone}`

  // No concrete date — a recurring time. Show the zone, no instant conversion.
  if (instant.value == null) return `${props.time} · ${props.zone}`

  const parts = [
    `${formatTimeInZone(instant.value, props.zone)} ${formatZoneAbbrev(instant.value, props.zone)} (${props.zone})`,
  ]
  if (viewerZone.value !== props.zone) {
    parts.push(`${formatTimeInZone(instant.value, viewerZone.value)} your time`)
  }
  return parts.join(' · ')
})
</script>

<template>
  <time :title="tooltip">{{ label }}</time>
</template>
