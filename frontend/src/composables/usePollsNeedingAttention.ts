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

    const datePolls = pool.getAll('datePoll')
    const items: PollItem[] = []

    for (const datePoll of datePolls) {
      if (datePoll.status === 'resolved') continue

      const event = pool.get('event', datePoll.eventId)
      if (!event) continue

      const dateRanges = pool
        .getAll('dateRange')
        .filter((dr) => dr.datePollId === datePoll.id)
      if (dateRanges.length === 0) continue

      const votes = pool.getAll('vote')
      const votedCount = dateRanges.filter((dr) =>
        votes.some((v) => v.dateRangeId === dr.id && v.userId === userId)
      ).length

      if (votedCount < dateRanges.length) {
        items.push({
          eventId: event.id,
          eventName: event.name,
          deadline: datePoll.deadline,
          votedCount,
          totalCount: dateRanges.length,
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
