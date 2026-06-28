import { computed, type Ref } from 'vue'
import { storeToRefs } from 'pinia'
import { useAuthStore } from '@/stores/auth'
import { useObjectPoolStore } from '@/stores'
import { useMinuteTicker } from './useMinuteTicker'

export interface UpcomingChoreItem {
  assignmentId: string
  choreId: string
  choreName: string
  eventId: string
  eventName: string
  date: string // YYYY-MM-DD
  time: string | null // "HH:MM" wall-clock, or null for an all-day chore
  day: 'today' | 'tomorrow'
  note: string | null
}

/**
 * How many chores the homepage renders before collapsing the rest into a
 * "+N more" hint. The list is ordered chronologically (today before tomorrow),
 * so slicing to this cap naturally lets today's chores crowd out tomorrow's —
 * tomorrow only shows when today leaves room.
 */
export const MAX_VISIBLE_CHORES = 4

// A timed chore is treated as done one hour after its time; an untimed chore
// at the end of its day. No manual check-off — these windows stand in for it.
const DONE_GRACE_MS = 60 * 60 * 1000

function pad(n: number): string {
  return String(n).padStart(2, '0')
}

function isoDate(d: Date): string {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
}

// The chore's nominal start as a local moment: its time on its date, or the
// start of the day when untimed. Drives chronological ordering.
function momentOf(date: string, time: string | null): number {
  const [y, m, d] = date.split('-').map(Number) as [number, number, number]
  if (time == null) return new Date(y, m - 1, d).getTime()
  const [hh, mm] = time.split(':').map(Number) as [number, number]
  return new Date(y, m - 1, d, hh, mm).getTime()
}

// The moment a chore counts as done (and drops off the list): an hour after a
// timed chore, or the next midnight for an untimed one.
function doneAt(date: string, time: string | null): number {
  if (time == null) {
    const [y, m, d] = date.split('-').map(Number) as [number, number, number]
    return new Date(y, m - 1, d + 1).getTime()
  }
  return momentOf(date, time) + DONE_GRACE_MS
}

/**
 * The current user's chores due today or tomorrow, across every event — what
 * the homepage surfaces during an event. Each item links back to its event's
 * chore roster.
 *
 * `now` is injectable for testing; in the app it's the shared minute ticker so
 * a timed chore drops off live, roughly an hour after it was due, without a
 * page refresh.
 */
export function useUpcomingChores(now: Ref<number> = useMinuteTicker().now) {
  const pool = useObjectPoolStore()
  const { currentUserId } = storeToRefs(useAuthStore())

  const upcomingChores = computed<UpcomingChoreItem[]>(() => {
    const userId = currentUserId.value
    if (!userId) return []

    const nowMs = now.value
    const nowDate = new Date(nowMs)
    const today = isoDate(nowDate)
    const tomorrow = isoDate(
      new Date(nowDate.getFullYear(), nowDate.getMonth(), nowDate.getDate() + 1)
    )

    // Index the join targets once.
    const choresById = new Map(pool.getAll('chore').map((c) => [c.id, c]))
    const rostersById = new Map(
      pool.getAll('choreRoster').map((r) => [r.id, r])
    )
    const eventsById = new Map(pool.getAll('event').map((e) => [e.id, e]))

    const items: UpcomingChoreItem[] = []
    for (const a of pool.getAll('choreAssignment')) {
      if (a.userId !== userId) continue
      if (a.date !== today && a.date !== tomorrow) continue

      const chore = choresById.get(a.choreId)
      if (!chore) continue
      if (nowMs >= doneAt(a.date, chore.time)) continue // already done

      const roster = rostersById.get(chore.choreRosterId)
      if (!roster) continue
      const event = eventsById.get(roster.eventId)
      if (!event) continue

      items.push({
        assignmentId: a.id,
        choreId: chore.id,
        choreName: chore.name,
        eventId: event.id,
        eventName: event.name,
        date: a.date,
        time: chore.time,
        day: a.date === today ? 'today' : 'tomorrow',
        note: a.note,
      })
    }

    items.sort(
      (x, y) =>
        momentOf(x.date, x.time) - momentOf(y.date, y.time) ||
        x.choreName.localeCompare(y.choreName)
    )
    return items
  })

  const visibleChores = computed(() =>
    upcomingChores.value.slice(0, MAX_VISIBLE_CHORES)
  )
  const hiddenCount = computed(
    () => upcomingChores.value.length - visibleChores.value.length
  )

  return { upcomingChores, visibleChores, hiddenCount }
}
