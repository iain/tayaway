<script setup lang="ts">
import { computed } from 'vue'
import { ChartBarIcon } from '@heroicons/vue/24/outline'
import SectionHeading from '@/components/common/SectionHeading.vue'
import BaseCard from '@/components/common/BaseCard.vue'
import type { PoolChore, PoolChoreAssignment, PoolMember } from '@/types/pool'

const props = defineProps<{
  chores: PoolChore[]
  assignments: PoolChoreAssignment[]
  members: PoolMember[]
}>()

interface SummaryRow {
  userId: string
  name: string
  counts: Map<string, number>
  total: number
}

const rows = computed<SummaryRow[]>(() => {
  const byUser = new Map<string, Map<string, number>>()

  for (const a of props.assignments) {
    let choreMap = byUser.get(a.userId)
    if (!choreMap) {
      choreMap = new Map()
      byUser.set(a.userId, choreMap)
    }
    choreMap.set(a.choreId, (choreMap.get(a.choreId) ?? 0) + 1)
  }

  const memberMap = new Map<string, PoolMember>()
  for (const m of props.members) {
    memberMap.set(m.userId, m)
  }

  const result: SummaryRow[] = []
  for (const [userId, counts] of byUser) {
    const member = memberMap.get(userId)
    let total = 0
    for (const c of counts.values()) total += c
    result.push({
      userId,
      name: member?.name ?? 'Unknown',
      counts,
      total,
    })
  }

  result.sort((a, b) => a.name.localeCompare(b.name))
  return result
})
</script>

<template>
  <div class="mt-8">
    <SectionHeading :icon="ChartBarIcon" title="Workload" />

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
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="(row, i) in rows"
            :key="row.userId"
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
          </tr>
        </tbody>
      </table>
    </BaseCard>
  </div>
</template>
