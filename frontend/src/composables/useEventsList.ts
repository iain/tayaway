import { computed } from 'vue'
import { useObjectPoolStore } from '@/stores'
import type { ObjectTypeMap } from '@/types/pool'

export function useEventsList() {
  const pool = useObjectPoolStore()

  const allEvents = computed(() => {
    void pool.version
    return pool.getAll('event')
  })

  const today = computed(() => new Date().toISOString().slice(0, 10))

  const upcomingEvents = computed(() =>
    allEvents.value
      .filter((e) => e.startDate && e.startDate >= today.value)
      .sort((a, b) => a.startDate!.localeCompare(b.startDate!))
  )

  const pastEvents = computed(() =>
    allEvents.value
      .filter((e) => e.startDate && e.startDate < today.value)
      .sort((a, b) => b.startDate!.localeCompare(a.startDate!))
  )

  const planningEvents = computed(() =>
    allEvents.value
      .filter((e) => !e.startDate)
      .sort(
        (a, b) =>
          new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()
      )
  )

  const hasEvents = computed(
    () =>
      upcomingEvents.value.length > 0 ||
      pastEvents.value.length > 0 ||
      planningEvents.value.length > 0
  )

  function getEventOwner(
    memberId: string
  ): ObjectTypeMap['member'] | undefined {
    return pool.get('member', memberId)
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
    upcomingEvents,
    pastEvents,
    planningEvents,
    hasEvents,
    getEventOwner,
    getDateRanges,
  }
}
