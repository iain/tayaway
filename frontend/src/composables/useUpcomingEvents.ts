import { computed } from 'vue'
import { storeToRefs } from 'pinia'
import { useAuthStore } from '@/stores/auth'
import { useObjectPoolStore } from '@/stores'
import { useEventsList } from './useEventsList'

export interface UpcomingEventItem {
  eventId: string
  eventName: string
  startDate: string
  endDate: string
  attendeeCount: number
  needsRsvp: boolean
}

export { formatDateRange as formatEventDateRange } from '@/utils/date'

export function useUpcomingEvents() {
  const pool = useObjectPoolStore()
  const { currentUserId } = storeToRefs(useAuthStore())
  const { upcomingEvents } = useEventsList()

  const items = computed<UpcomingEventItem[]>(() => {
    const userId = currentUserId.value

    // Single pass over attendances: going heads (members and guests) per
    // event + this user's answers. A row parked at pending by a date reset
    // counts as unanswered (doc/attendances.md).
    const attendeeCount = new Map<string, number>()
    const answeredByUser = new Set<string>()
    for (const a of pool.getAll('attendance')) {
      if (a.status === 'going') {
        attendeeCount.set(a.eventId, (attendeeCount.get(a.eventId) ?? 0) + 1)
      }
      if (userId && a.userId === userId && a.status !== 'pending') {
        answeredByUser.add(a.eventId)
      }
    }

    return upcomingEvents.value.map((event) => ({
      eventId: event.id,
      eventName: event.name,
      startDate: event.startDate!,
      endDate: event.endDate!,
      attendeeCount: attendeeCount.get(event.id) ?? 0,
      needsRsvp: userId != null && !answeredByUser.has(event.id),
    }))
  })

  return { upcomingEvents: items }
}
