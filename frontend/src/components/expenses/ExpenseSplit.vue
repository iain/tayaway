<script setup lang="ts">
import { computed } from 'vue'
import { useObjectPoolStore } from '@/stores/objectPool'
import { countNights } from '@/utils/event'
import type { PoolEvent } from '@/types/pool'

const props = defineProps<{
  event: PoolEvent
  total: number
}>()

const pool = useObjectPoolStore()

interface SplitRow {
  memberId: string
  name: string
  nights: number
  ratio: number
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

  const eventNights = countNights(props.event.startDate, props.event.endDate)

  const withNights = attendingRsvps.map((rsvp) => {
    const nights =
      rsvp.startDate && rsvp.endDate
        ? countNights(rsvp.startDate, rsvp.endDate)
        : eventNights
    return { rsvp, nights }
  })

  const totalNights = withNights.reduce((sum, row) => sum + row.nights, 0)
  if (totalNights === 0) return []

  const expenses = pool
    .getAll('expense')
    .filter((e) => e.eventId === props.event.id)

  return withNights.map(({ rsvp, nights }) => {
    const member = pool.get('member', rsvp.memberId)
    const ratio = nights / totalNights
    const paid = expenses
      .filter((e) => e.memberId === rsvp.memberId)
      .reduce((sum, e) => sum + e.amount, 0)
    return {
      memberId: rsvp.memberId,
      name: member?.name ?? member?.email ?? 'Unknown',
      nights,
      ratio,
      share: ratio * props.total,
      paid,
      balance: ratio * props.total - paid,
    }
  })
})

const totalNights = computed(() =>
  rows.value.reduce((sum, r) => sum + r.nights, 0)
)

function formatAmount(amount: number): string {
  return `€${amount.toFixed(2)}`
}

function formatNights(nights: number): string {
  return `${nights} night${nights === 1 ? '' : 's'}`
}

function formatPercent(ratio: number): string {
  return `${Math.round(ratio * 100)}%`
}

function formatBalance(balance: number): string {
  if (balance > 0.005) return `owes €${balance.toFixed(2)}`
  if (balance < -0.005) return `owed €${Math.abs(balance).toFixed(2)}`
  return 'settled'
}
</script>

<template>
  <div v-if="event.startDate && event.endDate" class="mt-8">
    <h2 class="mb-4 text-lg font-semibold text-gray-900 dark:text-white">
      Cost Split
    </h2>

    <p
      v-if="rows.length === 0"
      class="text-sm text-gray-500 dark:text-stone-400"
    >
      No attendees yet.
    </p>

    <div
      v-else
      data-testid="cost-split-table"
      class="overflow-hidden rounded-lg border border-gray-200 dark:border-stone-700"
    >
      <table class="w-full text-sm">
        <thead>
          <tr
            class="border-b border-gray-200 text-left text-xs font-medium tracking-wide text-gray-500 uppercase dark:border-stone-700 dark:text-stone-400"
          >
            <th class="pt-3 pr-4 pb-2 pl-2">Name</th>
            <th class="hidden pt-3 pr-4 pb-2 sm:table-cell">Nights</th>
            <th class="pt-3 pr-4 pb-2">Share</th>
            <th class="pt-3 pr-4 pb-2 text-right">Paid</th>
            <th class="pt-3 pr-4 pb-2 text-right">Fair share</th>
            <th class="pt-3 pr-2 pb-2 text-right">Balance</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="(row, i) in rows"
            :key="row.memberId"
            class="text-gray-800 dark:text-stone-200"
            :class="i % 2 === 0 ? 'bg-gray-50 dark:bg-black/20' : ''"
          >
            <td class="py-2 pr-4 pl-2 font-medium">{{ row.name }}</td>
            <td
              class="hidden py-2 pr-4 text-gray-600 sm:table-cell dark:text-stone-400"
            >
              {{ formatNights(row.nights) }}
            </td>
            <td class="py-2 pr-4 text-gray-600 dark:text-stone-400">
              {{ formatPercent(row.ratio) }}
            </td>
            <td
              class="py-2 pr-4 text-right font-mono text-gray-600 dark:text-stone-400"
            >
              {{ formatAmount(row.paid) }}
            </td>
            <td class="py-2 pr-4 text-right font-mono">
              {{ formatAmount(row.share) }}
            </td>
            <td
              class="py-2 pr-2 text-right font-mono"
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
            <td class="pt-2 pr-4 pb-3 pl-2">Total</td>
            <td
              class="hidden pt-2 pr-4 pb-3 text-gray-600 sm:table-cell dark:text-stone-400"
            >
              {{ formatNights(totalNights) }}
            </td>
            <td class="pt-2 pr-4 pb-3"></td>
            <td
              class="pt-2 pr-4 pb-3 text-right font-mono text-gray-600 dark:text-stone-400"
            >
              {{ formatAmount(total) }}
            </td>
            <td class="pt-2 pr-4 pb-3 text-right font-mono">
              {{ formatAmount(total) }}
            </td>
            <td class="pt-2 pr-2 pb-3"></td>
          </tr>
        </tfoot>
      </table>
    </div>
  </div>
</template>
