import { computed } from 'vue'
import { storeToRefs } from 'pinia'
import { useObjectPoolStore, useAuthStore } from '@/stores'

export interface RsvpEventItem {
  eventId: string
  eventName: string
  startDate: string
  endDate: string
}

export function formatEventDateRange(
  startDate: string,
  endDate: string
): string {
  const start = new Date(startDate)
  const end = new Date(endDate)
  const opts: Intl.DateTimeFormatOptions = { month: 'short', day: 'numeric' }

  if (start.getFullYear() === end.getFullYear()) {
    if (start.getMonth() === end.getMonth()) {
      return `${start.toLocaleDateString('en-US', opts)} – ${end.getDate()}, ${end.getFullYear()}`
    }
    return `${start.toLocaleDateString('en-US', opts)} – ${end.toLocaleDateString('en-US', opts)}, ${end.getFullYear()}`
  }

  return `${start.toLocaleDateString('en-US', { ...opts, year: 'numeric' })} – ${end.toLocaleDateString('en-US', { ...opts, year: 'numeric' })}`
}

export function useEventsNeedingRsvp() {
  const pool = useObjectPoolStore()
  const authStore = useAuthStore()
  const { currentMemberId } = storeToRefs(authStore)

  const eventsNeedingRsvp = computed<RsvpEventItem[]>(() => {
    void pool.version
    const memberId = currentMemberId.value
    if (!memberId) return []

    const rsvps = pool.getAll('rsvp')
    const items: RsvpEventItem[] = []

    const now = new Date()

    for (const event of pool.getAll('event')) {
      if (!event.startDate || !event.endDate) continue
      if (new Date(event.endDate) < now) continue

      const hasRsvp = rsvps.some(
        (r) => r.eventId === event.id && r.memberId === memberId
      )
      if (!hasRsvp) {
        items.push({
          eventId: event.id,
          eventName: event.name,
          startDate: event.startDate,
          endDate: event.endDate,
        })
      }
    }

    return items.sort(
      (a, b) =>
        new Date(a.startDate).getTime() - new Date(b.startDate).getTime()
    )
  })

  return { eventsNeedingRsvp }
}
