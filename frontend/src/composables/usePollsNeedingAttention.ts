import { computed } from 'vue'
import { storeToRefs } from 'pinia'
import { useAuthStore } from '@/stores/auth'
import { useObjectPoolStore } from '@/stores'

export interface PollItem {
  eventId: string
  eventName: string
  deadline: string
  votedCount: number
  totalCount: number
}

import { formatDeadline } from '@/utils/date'

export { formatDeadline }

export function isUrgent(deadline: string): boolean {
  const diffMs = new Date(deadline).getTime() - Date.now()
  return diffMs < 2 * 24 * 60 * 60 * 1000
}

export function isPastDeadline(deadline: string): boolean {
  return new Date(deadline).getTime() < Date.now()
}

export function usePollsNeedingAttention() {
  const pool = useObjectPoolStore()
  const authStore = useAuthStore()
  const { currentUserId } = storeToRefs(authStore)

  const pollsNeedingAttention = computed<PollItem[]>(() => {
    void pool.version
    const userId = currentUserId.value
    if (!userId) return []

    // Build a set of dateRangeIds the user has voted on — O(n) instead of O(n²)
    const votedDateRangeIds = new Set(
      pool
        .getAll('vote')
        .filter((v) => v.userId === userId)
        .map((v) => v.dateRangeId)
    )

    // Index dateRanges by datePollId — avoids re-scanning the full list per poll
    const rangesByPoll = new Map<string, [total: number, voted: number]>()
    for (const dr of pool.getAll('dateRange')) {
      const counts = rangesByPoll.get(dr.datePollId)
      const voted = votedDateRangeIds.has(dr.id) ? 1 : 0
      if (counts) {
        counts[0]++
        counts[1] += voted
      } else {
        rangesByPoll.set(dr.datePollId, [1, voted])
      }
    }

    const items: PollItem[] = []

    for (const datePoll of pool.getAll('datePoll')) {
      if (datePoll.status === 'resolved') continue

      const counts = rangesByPoll.get(datePoll.id)
      if (!counts || counts[0] === 0) continue

      const [totalCount, votedCount] = counts
      if (votedCount < totalCount) {
        const event = pool.get('event', datePoll.eventId)
        if (!event) continue

        items.push({
          eventId: event.id,
          eventName: event.name,
          deadline: datePoll.deadline,
          votedCount,
          totalCount,
        })
      }
    }

    return items.sort(
      (a, b) => new Date(a.deadline).getTime() - new Date(b.deadline).getTime()
    )
  })

  return {
    pollsNeedingAttention,
    formatDeadline,
    isUrgent,
    isPastDeadline,
  }
}
