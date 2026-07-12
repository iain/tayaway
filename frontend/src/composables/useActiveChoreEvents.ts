import { computed, type Ref } from 'vue'
import type { ObjectTypeMap } from '@/types/pool'
import { useEventsList } from './useEventsList'
import { useNow } from './useNow'

/**
 * The events whose rosters the standalone chores page shows: everything under
 * way today, or — when nothing is — the next event to start, so a roster can be
 * built before the trip begins. Events still date-polling have no dates to hang
 * a roster off and never qualify.
 */
export function useActiveChoreEvents(now: Ref<Date> = useNow().now) {
  const { currentEvents, upcomingEvents } = useEventsList(now)

  const activeEvents = computed<ObjectTypeMap['event'][]>(() =>
    currentEvents.value.length > 0
      ? currentEvents.value
      : upcomingEvents.value.slice(0, 1)
  )

  return { activeEvents }
}
