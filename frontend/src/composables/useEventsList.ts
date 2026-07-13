import { computed, type Ref } from 'vue'
import { useObjectPoolStore } from '@/stores'
import type { ObjectTypeMap } from '@/types/pool'
import { localIsoDate } from '@/utils/date'
import { useNow } from './useNow'

// `now` is injectable for testing; in the app it's the shared midnight ticker,
// so the current/upcoming split stays correct in a tab left open overnight.
export function useEventsList(now: Ref<Date> = useNow().now) {
  const pool = useObjectPoolStore()

  // Local calendar day, not the UTC one — an event that ended local-yesterday
  // must fall out of "current", and one starting local-today must appear, for
  // users far from UTC. Matches the day strings events carry.
  const today = computed(() => localIsoDate(now.value))

  // Single pass: categorize all events at once instead of four separate filters
  const categorized = computed(() => {
    const t = today.value
    const current: ObjectTypeMap['event'][] = []
    const upcoming: ObjectTypeMap['event'][] = []
    const past: ObjectTypeMap['event'][] = []
    const planning: ObjectTypeMap['event'][] = []

    for (const e of pool.getAll('event')) {
      if (e.startDate == null) {
        planning.push(e)
      } else if (e.startDate > t) {
        upcoming.push(e)
      } else if (e.endDate != null && e.endDate >= t) {
        current.push(e)
      } else {
        past.push(e)
      }
    }

    current.sort((a, b) => a.endDate!.localeCompare(b.endDate!))
    upcoming.sort((a, b) => a.startDate!.localeCompare(b.startDate!))
    past.sort((a, b) => b.startDate!.localeCompare(a.startDate!))
    planning.sort(
      (a, b) =>
        new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()
    )

    return { current, upcoming, past, planning }
  })

  const allEvents = computed(() => {
    return pool.getAll('event')
  })

  const currentEvents = computed(() => categorized.value.current)
  const upcomingEvents = computed(() => categorized.value.upcoming)
  const pastEvents = computed(() => categorized.value.past)
  const planningEvents = computed(() => categorized.value.planning)

  const hasEvents = computed(
    () =>
      currentEvents.value.length > 0 ||
      upcomingEvents.value.length > 0 ||
      pastEvents.value.length > 0 ||
      planningEvents.value.length > 0
  )

  function getEventOwner(userId: string): ObjectTypeMap['member'] | undefined {
    return pool.findBy('member', 'userId', userId)
  }

  function getDateRanges(eventId: string): ObjectTypeMap['dateRange'][] {
    const datePoll = pool
      .getAll('datePoll')
      .find((dp) => dp.eventId === eventId)
    if (!datePoll) return []
    return pool
      .getAll('dateRange')
      .filter((dr) => dr.datePollId === datePoll.id)
  }

  return {
    allEvents,
    currentEvents,
    upcomingEvents,
    pastEvents,
    planningEvents,
    hasEvents,
    getEventOwner,
    getDateRanges,
  }
}
