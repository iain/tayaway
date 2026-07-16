<script setup lang="ts">
import { computed } from 'vue'
import { CalculatorIcon } from '@heroicons/vue/24/outline'
import { useObjectPoolStore } from '@/stores/objectPool'
import { attendanceDates } from '@/utils/event'
import LedgerAmount from '@/components/common/LedgerAmount.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'
import BaseCard from '@/components/common/BaseCard.vue'
import type { HydratedEvent } from '@/composables/useHydratedEvent'

const props = defineProps<{
  event: HydratedEvent
  total: number
}>()

const pool = useObjectPoolStore()

/** A named guest itemized under their host's row: presence only — their
 *  share is billed to the host, so the money columns stay on that row. */
interface GuestSplitRow {
  attendanceId: string
  name: string
  days: number
}

interface SplitRow {
  userId: string
  name: string
  days: number
  guests: GuestSplitRow[]
  share: number
  paid: number
  balance: number
}

const rows = computed((): SplitRow[] => {
  if (!props.event.startDate || !props.event.endDate) return []

  const going = props.event.attendances.filter((a) => a.status === 'going')
  if (going.length === 0) return []

  const expenses = pool
    .getAll('expense')
    .filter((e) => e.eventId === props.event.id)

  // Per-expense splitting: compute each person's share across all expenses
  const shareByUser = new Map<string, number>()

  // Pre-compute each attendance's day set, resolved to the user its share
  // bills to (members bill themselves, guests their host — the hydrated
  // attendee is the sanctioned union reader). Member days feed the host
  // row's Days column; guest rows are itemized beneath it by name.
  const daySets = going.flatMap((attendance) => {
    const billing = attendance.attendee.billingUserId
    if (!billing) return []
    return [
      {
        attendanceId: attendance.id,
        attendeeName: attendance.attendee.name,
        billingUserId: billing,
        isGuest: attendance.attendee.isGuest,
        days: attendanceDates(
          attendance,
          props.event.startDate!,
          props.event.endDate!
        ),
      },
    ]
  })

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

    // Default: proportional to head-days within the expense window — every
    // going person (member or guest) is one head per attended day, billed
    // to their billing user.
    const headsByUser = new Map<string, number>()
    for (const { billingUserId, days } of daySets) {
      const heads = days.filter(
        (d) => d >= expense.startDate && d <= expense.endDate
      ).length
      if (heads > 0) {
        headsByUser.set(
          billingUserId,
          (headsByUser.get(billingUserId) ?? 0) + heads
        )
      }
    }

    const totalHeads = [...headsByUser.values()].reduce((s, h) => s + h, 0)
    if (totalHeads === 0) continue

    for (const [userId, heads] of headsByUser) {
      const share = (heads / totalHeads) * expense.amount
      shareByUser.set(userId, (shareByUser.get(userId) ?? 0) + share)
    }
  }

  // One row per billing user, carrying their own attended days and their
  // named guests for itemization.
  const rowByUser = new Map<string, { days: number; guests: GuestSplitRow[] }>()
  for (const {
    attendanceId,
    attendeeName,
    billingUserId,
    isGuest,
    days,
  } of daySets) {
    const acc = rowByUser.get(billingUserId) ?? { days: 0, guests: [] }
    if (isGuest) {
      acc.guests.push({ attendanceId, name: attendeeName, days: days.length })
    } else {
      acc.days += days.length
    }
    rowByUser.set(billingUserId, acc)
  }

  return [...rowByUser].map(([userId, { days, guests }]) => {
    const member = pool.findBy('member', 'userId', userId)
    const share = shareByUser.get(userId) ?? 0
    const paid = expenses
      .filter((e) => e.userId === userId)
      .reduce((sum, e) => sum + e.amount, 0)
    return {
      userId,
      name: member?.name ?? member?.email ?? 'Unknown',
      days,
      guests,
      share,
      paid,
      balance: share - paid,
    }
  })
})

// Head-days across everyone, member or guest — the denominator the
// proportional split divides by.
const totalDays = computed(() =>
  rows.value.reduce(
    (sum, r) => sum + r.days + r.guests.reduce((s, g) => s + g.days, 0),
    0
  )
)

function formatDays(days: number): string {
  return `${days} day${days === 1 ? '' : 's'}`
}
</script>

<template>
  <div v-if="event.startDate && event.endDate" class="mt-8">
    <SectionHeading :icon="CalculatorIcon" title="Fair shares" />

    <p v-if="rows.length === 0" class="text-ink-muted text-sm">
      No attendees yet.
    </p>

    <BaseCard v-else data-testid="cost-split-table" class="overflow-hidden">
      <table class="w-full text-sm">
        <thead>
          <tr
            class="border-line text-ink-muted border-b text-left text-xs font-medium tracking-wide uppercase"
          >
            <th class="pt-3 pr-4 pb-2 pl-4">Name</th>
            <th class="hidden pt-3 pr-4 pb-2 sm:table-cell">Days</th>
            <th class="pt-3 pr-4 pb-2 text-right whitespace-nowrap">Paid</th>
            <th class="hidden pt-3 pr-4 pb-2 text-right sm:table-cell">
              Fair share
            </th>
            <th class="pt-3 pr-4 pb-2 text-right whitespace-nowrap">Balance</th>
          </tr>
        </thead>
        <tbody class="divide-line-faint divide-y">
          <template v-for="row in rows" :key="row.userId">
            <tr class="text-ink">
              <td
                class="max-w-[8rem] truncate py-2 pr-4 pl-4 font-medium sm:max-w-none"
              >
                {{ row.name }}
              </td>
              <td class="text-ink-muted hidden py-2 pr-4 sm:table-cell">
                {{ formatDays(row.days) }}
              </td>
              <td class="text-ink-muted py-2 pr-4 text-right whitespace-nowrap">
                <LedgerAmount :amount="row.paid" />
              </td>
              <td
                class="hidden py-2 pr-4 text-right whitespace-nowrap sm:table-cell"
              >
                <LedgerAmount :amount="row.share" />
              </td>
              <td
                class="py-2 pr-4 text-right font-semibold whitespace-nowrap"
                :class="{
                  'text-ink-faint': Math.abs(row.balance) <= 0.005,
                }"
              >
                <template v-if="row.balance > 0.005"
                  ><span class="sr-only sm:not-sr-only sm:inline">owes </span
                  ><LedgerAmount :amount="row.balance"
                /></template>
                <template v-else-if="row.balance < -0.005"
                  ><span class="sr-only sm:not-sr-only sm:inline">is owed </span
                  ><LedgerAmount :amount="Math.abs(row.balance)"
                /></template>
                <template v-else>even</template>
              </td>
            </tr>
            <!-- Named guests, itemized under their host; their share is
                 already inside the host's money columns above. -->
            <tr
              v-for="guest in row.guests"
              :key="guest.attendanceId"
              data-testid="split-guest-row"
              class="text-ink-muted"
            >
              <td class="max-w-[8rem] truncate py-2 pr-4 pl-8 sm:max-w-none">
                {{ guest.name }}
                <span class="text-ink-faint text-xs">
                  (guest of {{ row.name }})
                </span>
              </td>
              <td class="hidden py-2 pr-4 sm:table-cell">
                {{ formatDays(guest.days) }}
              </td>
              <td class="text-ink-faint py-2 pr-4 text-right">—</td>
              <td
                class="text-ink-faint hidden py-2 pr-4 text-right sm:table-cell"
              >
                —
              </td>
              <td class="text-ink-faint py-2 pr-4 text-right">—</td>
            </tr>
          </template>
        </tbody>
        <tfoot>
          <tr class="border-line text-ink border-t font-semibold">
            <td class="pt-2 pr-4 pb-3 pl-4">Total</td>
            <td class="text-ink-muted hidden pt-2 pr-4 pb-3 sm:table-cell">
              {{ formatDays(totalDays) }}
            </td>
            <td class="text-ink-muted pt-2 pr-4 pb-3 text-right">
              <LedgerAmount :amount="total" />
            </td>
            <td class="hidden pt-2 pr-4 pb-3 text-right sm:table-cell">
              <LedgerAmount :amount="total" />
            </td>
            <td class="pt-2 pr-4 pb-3"></td>
          </tr>
        </tfoot>
      </table>
    </BaseCard>
  </div>
</template>
