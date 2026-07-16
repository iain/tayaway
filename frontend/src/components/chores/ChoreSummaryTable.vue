<script setup lang="ts">
import { computed } from 'vue'
import { ChartBarIcon } from '@heroicons/vue/24/outline'
import SectionHeading from '@/components/common/SectionHeading.vue'
import BaseCard from '@/components/common/BaseCard.vue'
import type {
  PoolChore,
  PoolChoreAssignment,
  PoolEvent,
  PoolMember,
} from '@/types/pool'
import type { HydratedAttendance } from '@/composables/useHydratedEvent'
import { assignmentPerson, holderAttendanceId } from '@/utils/chores'
import { attendanceDates } from '@/utils/event'

const props = withDefaults(
  defineProps<{
    chores: PoolChore[]
    assignments: PoolChoreAssignment[]
    // Legacy fallback for rows written before the attendance link existed.
    members: PoolMember[]
    attendances: HydratedAttendance[]
    event: PoolEvent
    headingLevel?: 2 | 3
  }>(),
  { headingLevel: 2 }
)

interface SummaryRow {
  key: string
  name: string
  counts: Map<string, number>
  total: number
  daysThere: number
  /** total ÷ daysThere, formatted; "—" for someone with no attended days. */
  perDay: string
}

const rows = computed<SummaryRow[]>(() => {
  const attendanceById = new Map<string, HydratedAttendance>()
  const byUser = new Map<string, string>()
  for (const a of props.attendances) {
    attendanceById.set(a.id, a)
    if (a.userId) byUser.set(a.userId, a.id)
  }
  const memberMap = new Map<string, PoolMember>()
  for (const m of props.members) {
    memberMap.set(m.userId, m)
  }

  // One row per attendee, keyed by their attendance; legacy assignments that
  // resolve to nobody share a per-user bucket so their work still shows.
  const rowKey = (a: PoolChoreAssignment) =>
    holderAttendanceId(a, byUser) ?? `user:${a.userId}`

  const countsByKey = new Map<string, Map<string, number>>()
  for (const a of props.assignments) {
    const key = rowKey(a)
    let choreMap = countsByKey.get(key)
    if (!choreMap) {
      choreMap = new Map()
      countsByKey.set(key, choreMap)
    }
    choreMap.set(a.choreId, (choreMap.get(a.choreId) ?? 0) + 1)
  }

  // Days attended per attendee, so a light total next to a short stay reads
  // as fair rather than as someone shirking — auto-fill balances load against
  // exactly this number.
  const daysByKey = new Map<string, number>()
  if (props.event.startDate && props.event.endDate) {
    for (const attendance of props.attendances) {
      const days = attendanceDates(
        attendance,
        props.event.startDate,
        props.event.endDate
      )
      if (days.length > 0) daysByKey.set(attendance.id, days.length)
    }
  }

  // Attendees without a single chore still get a row — their 0.0/day IS the
  // fairness signal (this table replaced the "X has no upcoming chores" nudge).
  for (const key of daysByKey.keys()) {
    if (!countsByKey.has(key)) countsByKey.set(key, new Map())
  }

  const result: SummaryRow[] = []
  for (const [key, counts] of countsByKey) {
    const attendance = attendanceById.get(key)
    const name = attendance
      ? attendance.attendee.name
      : assignmentPerson(
          { attendanceId: null, userId: key.replace(/^user:/, '') },
          attendanceById,
          memberMap
        ).name
    let total = 0
    for (const c of counts.values()) total += c
    const daysThere = daysByKey.get(key) ?? 0
    result.push({
      key,
      name,
      counts,
      total,
      daysThere,
      perDay: daysThere > 0 ? (total / daysThere).toFixed(1) : '—',
    })
  }

  result.sort((a, b) => b.total - a.total || a.name.localeCompare(b.name))
  return result
})
</script>

<template>
  <div class="mt-8" data-testid="chore-summary-table">
    <SectionHeading
      :icon="ChartBarIcon"
      title="Workload"
      :heading-level="headingLevel"
    />

    <BaseCard class="overflow-x-auto">
      <table class="min-w-full text-sm">
        <caption class="sr-only">
          Workload summary: how many chore-days each person is assigned.
        </caption>
        <thead>
          <tr
            class="border-line text-ink-muted border-b text-left text-xs font-medium tracking-wide uppercase"
          >
            <th scope="col" class="pt-3 pr-4 pb-2 pl-4">Name</th>
            <th
              v-for="chore in chores"
              :key="chore.id"
              scope="col"
              class="pt-3 pr-4 pb-2 text-right whitespace-nowrap"
            >
              {{ chore.name }}
            </th>
            <th scope="col" class="pt-3 pr-4 pb-2 text-right">Total</th>
            <th scope="col" class="pt-3 pr-4 pb-2 text-right whitespace-nowrap">
              Days there
            </th>
            <th scope="col" class="pt-3 pr-4 pb-2 text-right whitespace-nowrap">
              Per day
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="(row, i) in rows"
            :key="row.key"
            class="text-ink"
            :class="i % 2 === 0 ? 'bg-surface-sunken' : ''"
          >
            <th
              scope="row"
              class="max-w-[8rem] truncate py-2 pr-4 pl-4 text-left font-medium sm:max-w-none"
            >
              {{ row.name }}
            </th>
            <td
              v-for="chore in chores"
              :key="chore.id"
              class="py-2 pr-4 text-right tabular-nums"
            >
              {{ row.counts.get(chore.id) ?? 0 }}
            </td>
            <td class="py-2 pr-4 text-right font-semibold tabular-nums">
              {{ row.total }}
            </td>
            <td class="text-ink-muted py-2 pr-4 text-right tabular-nums">
              {{ row.daysThere }}
            </td>
            <td class="py-2 pr-4 text-right tabular-nums">
              {{ row.perDay }}
            </td>
          </tr>
        </tbody>
      </table>
    </BaseCard>
  </div>
</template>
