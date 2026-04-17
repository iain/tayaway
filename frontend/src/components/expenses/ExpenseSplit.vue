<script setup lang="ts">
import { computed } from 'vue'
import { CalculatorIcon } from '@heroicons/vue/24/outline'
import { useObjectPoolStore } from '@/stores/objectPool'
import { countDays } from '@/utils/event'
import { formatAmount } from '@/utils/format'
import SectionHeading from '@/components/common/SectionHeading.vue'
import BaseCard from '@/components/common/BaseCard.vue'
import type { PoolEvent } from '@/types/pool'

const props = defineProps<{
  event: PoolEvent
  total: number
}>()

const pool = useObjectPoolStore()

interface SplitRow {
  userId: string
  name: string
  days: number
  share: number
  paid: number
  balance: number
}

const rows = computed((): SplitRow[] => {
  if (!props.event.startDate || !props.event.endDate) return []

  const attendingRsvps = pool
    .getAll('rsvp')
    .filter((r) => r.eventId === props.event.id && r.attending)

  if (attendingRsvps.length === 0) return []

  const eventDays = countDays(props.event.startDate, props.event.endDate)

  const expenses = pool
    .getAll('expense')
    .filter((e) => e.eventId === props.event.id)

  // Per-expense splitting: compute each person's share across all expenses
  const shareByUser = new Map<string, number>()

  // Pre-compute each RSVP's effective dates
  const rsvpDates = attendingRsvps.map((rsvp) => ({
    rsvp,
    start: rsvp.startDate ?? props.event.startDate!,
    end: rsvp.endDate ?? props.event.endDate!,
    days:
      rsvp.startDate && rsvp.endDate
        ? countDays(rsvp.startDate, rsvp.endDate)
        : eventDays,
  }))

  // For each expense, compute overlap and distribute cost
  for (const expense of expenses) {
    // If expense has explicit participants, factor-weighted split
    const participantIds = expense.participantIds ?? []
    if (participantIds.length > 0) {
      const participants = participantIds
        .map((pid) => pool.get('expenseParticipant', pid))
        .filter((p) => p != null)

      const totalFactor = participants.reduce((s, p) => s + p.factor, 0)
      if (participants.length > 0 && totalFactor > 0) {
        for (const p of participants) {
          const share = (p.factor / totalFactor) * expense.amount
          shareByUser.set(p.userId, (shareByUser.get(p.userId) ?? 0) + share)
        }
      }
      continue
    }

    // Default: RSVP overlap logic
    const overlaps: { userId: string; overlapDays: number }[] = []

    for (const { rsvp, start, end } of rsvpDates) {
      const overlapStart = expense.startDate > start ? expense.startDate : start
      const overlapEnd = expense.endDate < end ? expense.endDate : end

      if (overlapStart > overlapEnd) continue

      const overlapDays = countDays(overlapStart, overlapEnd)
      if (overlapDays > 0) {
        overlaps.push({ userId: rsvp.userId, overlapDays })
      }
    }

    const totalOverlapDays = overlaps.reduce((sum, o) => sum + o.overlapDays, 0)
    if (totalOverlapDays === 0) continue

    for (const { userId, overlapDays } of overlaps) {
      const share = (overlapDays / totalOverlapDays) * expense.amount
      shareByUser.set(userId, (shareByUser.get(userId) ?? 0) + share)
    }
  }

  return rsvpDates.map(({ rsvp, days }) => {
    const member = pool.findBy('member', 'userId', rsvp.userId)
    const share = shareByUser.get(rsvp.userId) ?? 0
    const paid = expenses
      .filter((e) => e.userId === rsvp.userId)
      .reduce((sum, e) => sum + e.amount, 0)
    return {
      userId: rsvp.userId,
      name: member?.name ?? member?.email ?? 'Unknown',
      days,
      share,
      paid,
      balance: share - paid,
    }
  })
})

const totalDays = computed(() => rows.value.reduce((sum, r) => sum + r.days, 0))

function formatDays(days: number): string {
  return `${days} day${days === 1 ? '' : 's'}`
}

function formatBalance(balance: number): string {
  if (balance > 0.005) return `owes €${balance.toFixed(2)}`
  if (balance < -0.005) return `owed €${Math.abs(balance).toFixed(2)}`
  return 'settled'
}
</script>

<template>
  <div v-if="event.startDate && event.endDate" class="mt-8">
    <SectionHeading :icon="CalculatorIcon" title="Cost Split" />

    <p
      v-if="rows.length === 0"
      class="text-sm text-gray-500 dark:text-stone-400"
    >
      No attendees yet.
    </p>

    <BaseCard v-else data-testid="cost-split-table" class="overflow-hidden">
      <table class="w-full text-sm">
        <thead>
          <tr
            class="border-b border-gray-200 text-left text-xs font-medium tracking-wide text-gray-500 uppercase dark:border-stone-700 dark:text-stone-400"
          >
            <th class="pt-3 pr-4 pb-2 pl-4">Name</th>
            <th class="hidden pt-3 pr-4 pb-2 sm:table-cell">Days</th>
            <th class="pt-3 pr-4 pb-2 text-right whitespace-nowrap">Paid</th>
            <th class="pt-3 pr-4 pb-2 text-right">
              <span class="sm:hidden">Share</span>
              <span class="hidden sm:inline">Fair share</span>
            </th>
            <th class="pt-3 pr-4 pb-2 text-right whitespace-nowrap">Balance</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="(row, i) in rows"
            :key="row.userId"
            class="text-gray-800 dark:text-stone-200"
            :class="i % 2 === 0 ? 'bg-gray-50 dark:bg-white/[0.04]' : ''"
          >
            <td
              class="max-w-[8rem] truncate py-2 pr-4 pl-4 font-medium sm:max-w-none"
            >
              {{ row.name }}
            </td>
            <td
              class="hidden py-2 pr-4 text-gray-600 sm:table-cell dark:text-stone-400"
            >
              {{ formatDays(row.days) }}
            </td>
            <td
              class="py-2 pr-4 text-right font-mono whitespace-nowrap text-gray-600 dark:text-stone-400"
            >
              {{ formatAmount(row.paid) }}
            </td>
            <td class="py-2 pr-4 text-right font-mono whitespace-nowrap">
              {{ formatAmount(row.share) }}
            </td>
            <td
              class="py-2 pr-4 text-right font-mono font-semibold"
              :class="{
                'text-red-600 dark:text-red-400': row.balance > 0.005,
                'text-green-600 dark:text-green-400': row.balance < -0.005,
                'text-gray-400 dark:text-stone-500':
                  Math.abs(row.balance) <= 0.005,
              }"
            >
              {{ formatBalance(row.balance) }}
            </td>
          </tr>
        </tbody>
        <tfoot>
          <tr
            class="border-t border-gray-300 font-semibold text-gray-900 dark:border-stone-600 dark:text-white"
          >
            <td class="pt-2 pr-4 pb-3 pl-4">Total</td>
            <td
              class="hidden pt-2 pr-4 pb-3 text-gray-600 sm:table-cell dark:text-stone-400"
            >
              {{ formatDays(totalDays) }}
            </td>
            <td
              class="pt-2 pr-4 pb-3 text-right font-mono text-gray-600 dark:text-stone-400"
            >
              {{ formatAmount(total) }}
            </td>
            <td class="pt-2 pr-4 pb-3 text-right font-mono">
              {{ formatAmount(total) }}
            </td>
            <td class="pt-2 pr-4 pb-3"></td>
          </tr>
        </tfoot>
      </table>
    </BaseCard>
  </div>
</template>
