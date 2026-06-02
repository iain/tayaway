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

    // Single pass over RSVPs: attending counts per event + this user's responses
    const attendeeCount = new Map<string, number>()
    const rsvpedByUser = new Set<string>()
    for (const r of pool.getAll('rsvp')) {
      if (r.attending) {
        attendeeCount.set(r.eventId, (attendeeCount.get(r.eventId) ?? 0) + 1)
      }
      if (userId && r.userId === userId) {
        rsvpedByUser.add(r.eventId)
      }
    }

    return upcomingEvents.value.map((event) => ({
      eventId: event.id,
      eventName: event.name,
      startDate: event.startDate!,
      endDate: event.endDate!,
      attendeeCount: attendeeCount.get(event.id) ?? 0,
      needsRsvp: userId != null && !rsvpedByUser.has(event.id),
    }))
  })

  return { upcomingEvents: items }
}
