import { computed, type ComputedRef } from 'vue'
import { useObjectPoolStore } from '@/stores/objectPool'

/**
 * Whether an event still has money in flight — either expenses nobody has
 * settled up yet, or a settlement whose transfers haven't all been paid.
 *
 * This is the shared definition of "the books are still open on this event".
 * The dashboard lists past events that match as needing attention, and it's
 * what keeps an event in focus through the expense-filing tail that follows
 * a trip (see `useFocusedEvent`).
 */
export function useOpenExpenses(): {
  unsettledExpenseCountByEvent: ComputedRef<Map<string, number>>
  unpaidTransferCountByEvent: ComputedRef<Map<string, number>>
  hasOpenExpenses: (eventId: string) => boolean
} {
  const pool = useObjectPoolStore()

  // Both maps are built in one pass over their source collection rather than
  // per event — O(expenses) and O(settlements + transfers) instead of
  // O(events × …), which matters on the dashboard's full event list.
  const unsettledExpenseCountByEvent = computed<Map<string, number>>(() => {
    const counts = new Map<string, number>()
    for (const e of pool.getAll('expense')) {
      if (!e.settlementId) {
        counts.set(e.eventId, (counts.get(e.eventId) ?? 0) + 1)
      }
    }
    return counts
  })

  const unpaidTransferCountByEvent = computed<Map<string, number>>(() => {
    const eventBySettlement = new Map<string, string>()
    for (const s of pool.getAll('settlement')) {
      eventBySettlement.set(s.id, s.eventId)
    }
    const counts = new Map<string, number>()
    for (const t of pool.getAll('settlementTransfer')) {
      // A superseded transfer was replaced by a recalculated one; only the
      // live row still represents a debt.
      if (!t.paidAt && !t.supersededAt) {
        const eventId = eventBySettlement.get(t.settlementId)
        if (eventId) {
          counts.set(eventId, (counts.get(eventId) ?? 0) + 1)
        }
      }
    }
    return counts
  })

  function hasOpenExpenses(eventId: string): boolean {
    return (
      (unsettledExpenseCountByEvent.value.get(eventId) ?? 0) > 0 ||
      (unpaidTransferCountByEvent.value.get(eventId) ?? 0) > 0
    )
  }

  return {
    unsettledExpenseCountByEvent,
    unpaidTransferCountByEvent,
    hasOpenExpenses,
  }
}
