import { computed, type Ref } from 'vue'
import { storeToRefs } from 'pinia'
import { useAuthStore } from '@/stores/auth'
import { useObjectPoolStore } from '@/stores'
import { useMinuteTicker } from './useMinuteTicker'
import { zonedDateString, wallClockToEpoch } from '@/utils/timezone'
import { addDays } from '@/utils/date'

export interface UpcomingChoreItem {
  assignmentId: string
  choreId: string
  choreName: string
  eventId: string
  eventName: string
  date: string // YYYY-MM-DD
  time: string | null // "HH:MM" wall-clock, or null for an all-day chore
  // The event's IANA zone — the chore's time and day are reckoned in it.
  timezone: string
  day: 'today' | 'tomorrow'
  note: string | null
  // Set when the chore belongs to a guest the user hosts — their reminders
  // land on the host, so the host's list carries them too.
  guestName: string | null
}

/**
 * How many chores the homepage renders before collapsing the rest into a
 * "+N more" hint. The list is ordered chronologically (today before tomorrow),
 * so slicing to this cap naturally lets today's chores crowd out tomorrow's —
 * tomorrow only shows when today leaves room.
 */
export const MAX_VISIBLE_CHORES = 4

// A timed chore is treated as done an hour after its time; an untimed chore at
// the end of its day. No manual check-off — these windows stand in for it.
const DONE_GRACE_MS = 60 * 60 * 1000

/**
 * The current user's chores due today or tomorrow, across every event — what
 * the homepage surfaces during an event — plus those of any guests they
 * host, named as such. "Today"/"tomorrow" and the done-window are reckoned
 * in each event's own zone, so a traveller (or a chore in another region) is
 * bucketed by the event's local day, not the device's. Each item links back
 * to its event's roster.
 *
 * `now` is injectable for testing; in the app it's the shared minute ticker so
 * a timed chore drops off live, roughly an hour after it was due.
 */
export function useUpcomingChores(now: Ref<number> = useMinuteTicker().now) {
  const pool = useObjectPoolStore()
  const { currentUserId } = storeToRefs(useAuthStore())

  const upcomingChores = computed<UpcomingChoreItem[]>(() => {
    const userId = currentUserId.value
    if (!userId) return []

    const nowMs = now.value
    const choresById = new Map(pool.getAll('chore').map((c) => [c.id, c]))
    const rostersById = new Map(
      pool.getAll('choreRoster').map((r) => [r.id, r])
    )
    const eventsById = new Map(pool.getAll('event').map((e) => [e.id, e]))

    // Assignments are keyed by the attendance behind the holder; collect the
    // user's member attendance rows across events, plus the guests they host
    // (whose reminders land on the host). Legacy rows without the link still
    // match on their mirrored userId.
    const myAttendanceIds = new Set<string>()
    const hostedGuestNameByAttendance = new Map<string, string>()
    for (const attendance of pool.getAll('attendance')) {
      if (attendance.userId === userId) {
        myAttendanceIds.add(attendance.id)
      } else if (attendance.guestId && attendance.hostUserId === userId) {
        const guest = pool.get('guest', attendance.guestId)
        hostedGuestNameByAttendance.set(
          attendance.id,
          guest?.name ?? 'your guest'
        )
      }
    }
    // Whose list this row belongs on: `mine`, `guest` (hosted), or neither.
    const claim = (a: {
      attendanceId: string | null
      userId: string | null
    }): { guestName: string | null } | null => {
      if (a.attendanceId) {
        if (myAttendanceIds.has(a.attendanceId)) return { guestName: null }
        const guestName = hostedGuestNameByAttendance.get(a.attendanceId)
        return guestName ? { guestName } : null
      }
      return a.userId === userId ? { guestName: null } : null
    }

    // "today"/"tomorrow" depend on the event's zone; memoise per zone.
    const windowByZone = new Map<string, { today: string; tomorrow: string }>()
    const windowFor = (zone: string) => {
      let w = windowByZone.get(zone)
      if (!w) {
        const today = zonedDateString(nowMs, zone)
        w = { today, tomorrow: addDays(today, 1) }
        windowByZone.set(zone, w)
      }
      return w
    }

    const rows: { item: UpcomingChoreItem; sort: number }[] = []
    for (const a of pool.getAll('choreAssignment')) {
      const claimed = claim(a)
      if (!claimed) continue

      const chore = choresById.get(a.choreId)
      if (!chore) continue
      const roster = rostersById.get(chore.choreRosterId)
      if (!roster) continue
      const event = eventsById.get(roster.eventId)
      if (!event) continue

      const zone = event.timezone
      const { today, tomorrow } = windowFor(zone)
      if (a.date !== today && a.date !== tomorrow) continue

      const doneAt = chore.time
        ? wallClockToEpoch(a.date, chore.time, zone) + DONE_GRACE_MS
        : wallClockToEpoch(addDays(a.date, 1), null, zone) // next local midnight
      if (nowMs >= doneAt) continue // already done

      rows.push({
        item: {
          assignmentId: a.id,
          choreId: chore.id,
          choreName: chore.name,
          eventId: event.id,
          eventName: event.name,
          date: a.date,
          time: chore.time,
          timezone: zone,
          day: a.date === today ? 'today' : 'tomorrow',
          note: a.note,
          guestName: claimed.guestName,
        },
        sort: wallClockToEpoch(a.date, chore.time, zone),
      })
    }

    rows.sort(
      (x, y) =>
        x.sort - y.sort || x.item.choreName.localeCompare(y.item.choreName)
    )
    return rows.map((r) => r.item)
  })

  const visibleChores = computed(() =>
    upcomingChores.value.slice(0, MAX_VISIBLE_CHORES)
  )
  const hiddenCount = computed(
    () => upcomingChores.value.length - visibleChores.value.length
  )

  return { upcomingChores, visibleChores, hiddenCount }
}
