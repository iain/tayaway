import { computed } from 'vue'
import { storeToRefs } from 'pinia'
import { useAuthStore } from '@/stores/auth'
import { useObjectPoolStore } from '@/stores'
import { useNow } from './useNow'

export interface RsvpEventItem {
  eventId: string
  eventName: string
  startDate: string
  endDate: string
}

export { formatDateRange as formatEventDateRange } from '@/utils/date'

export function useEventsNeedingRsvp() {
  const pool = useObjectPoolStore()
  const authStore = useAuthStore()
  const { currentUserId } = storeToRefs(authStore)
  const { now } = useNow()

  const eventsNeedingRsvp = computed<RsvpEventItem[]>(() => {
    const userId = currentUserId.value
    if (!userId) return []

    // Build set of eventIds the user has answered — O(1) lookup per event.
    // "No response" now has two forms (doc/attendances.md): no attendance
    // row at all, or a row reverted to pending by a date reset.
    const answeredEventIds = new Set(
      pool
        .getAll('attendance')
        .filter((a) => a.userId === userId && a.status !== 'pending')
        .map((a) => a.eventId)
    )

    const items: RsvpEventItem[] = []
    const currentNow = now.value

    for (const event of pool.getAll('event')) {
      if (!event.startDate || !event.endDate) continue
      if (new Date(event.endDate) < currentNow) continue
      if (answeredEventIds.has(event.id)) continue

      items.push({
        eventId: event.id,
        eventName: event.name,
        startDate: event.startDate,
        endDate: event.endDate,
      })
    }

    return items.sort(
      (a, b) =>
        new Date(a.startDate).getTime() - new Date(b.startDate).getTime()
    )
  })

  return { eventsNeedingRsvp }
}
