import { computed } from 'vue'
import { storeToRefs } from 'pinia'
import { useAuthStore } from '@/stores/auth'
import { useObjectPoolStore } from '@/stores'

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

  const eventsNeedingRsvp = computed<RsvpEventItem[]>(() => {
    void pool.version
    const userId = currentUserId.value
    if (!userId) return []

    // Build set of eventIds the user has RSVPed to — O(1) lookup per event
    const rsvpedEventIds = new Set(
      pool
        .getAll('rsvp')
        .filter((r) => r.userId === userId)
        .map((r) => r.eventId)
    )

    const items: RsvpEventItem[] = []
    const now = new Date()

    for (const event of pool.getAll('event')) {
      if (!event.startDate || !event.endDate) continue
      if (new Date(event.endDate) < now) continue
      if (rsvpedEventIds.has(event.id)) continue

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
