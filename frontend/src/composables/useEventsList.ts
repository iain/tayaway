import { computed } from 'vue'
import { useObjectPoolStore } from '@/stores'
import type { ObjectTypeMap } from '@/types/pool'
import {
  eventIsCurrent,
  eventIsUpcoming,
  eventIsPast,
  eventIsPlanning,
} from '@/utils/event'

export function useEventsList() {
  const pool = useObjectPoolStore()

  const allEvents = computed(() => {
    void pool.version
    return pool.getAll('event')
  })

  const today = computed(() => new Date().toISOString().slice(0, 10))

  const currentEvents = computed(() =>
    allEvents.value
      .filter((e) => eventIsCurrent(e, today.value))
      .sort((a, b) => a.endDate!.localeCompare(b.endDate!))
  )

  const upcomingEvents = computed(() =>
    allEvents.value
      .filter((e) => eventIsUpcoming(e, today.value))
      .sort((a, b) => a.startDate!.localeCompare(b.startDate!))
  )

  const pastEvents = computed(() =>
    allEvents.value
      .filter((e) => eventIsPast(e, today.value))
      .sort((a, b) => b.startDate!.localeCompare(a.startDate!))
  )

  const planningEvents = computed(() =>
    allEvents.value
      .filter((e) => eventIsPlanning(e))
      .sort(
        (a, b) =>
          new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()
      )
  )

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
