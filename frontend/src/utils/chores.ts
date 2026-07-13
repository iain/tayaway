import type { PoolChore, PoolChoreAssignment, PoolRsvp } from '@/types/pool'
import { attendedDates } from '@/utils/event'
import { wallClockToEpoch } from '@/utils/timezone'

/**
 * The subset of `assignments` a re-fill or clear-upcoming can actually touch:
 * today onward, minus today's occurrence of any timed chore that has already
 * started (in the event's zone). The server treats a started chore's rows as
 * the record of who did it, exactly like a past day — counts and nudges built
 * on this stay honest about what those actions would really change.
 */
export function refillableAssignments<
  A extends Pick<PoolChoreAssignment, 'choreId' | 'date'>,
>(
  assignments: readonly A[],
  chores: ReadonlyArray<Pick<PoolChore, 'id' | 'time'>>,
  today: string,
  zone: string,
  nowMs: number
): A[] {
  const timeByChore = new Map(chores.map((c) => [c.id, c.time]))
  return assignments.filter((a) => {
    if (a.date < today) return false
    if (a.date > today) return true
    const time = timeByChore.get(a.choreId)
    return !time || wallClockToEpoch(a.date, time, zone) > nowMs
  })
}

/**
 * Whether the chores page should nudge the user toward auto-fill: the roster
 * has seats and fewer than half of them are filled. Fills in either direction
 * (auto-fill or by hand) make the nudge disappear on its own, so it needs no
 * dismissal state.
 */
/**
 * The user ids attending on one specific day, per their attending RSVPs —
 * the eligibility set for assigning (or reassigning) that day's chores.
 * Mirrors the backend autofill's availability map for a single date.
 */
export function attendingUserIdsOn(
  date: string,
  rsvps: ReadonlyArray<
    Pick<PoolRsvp, 'userId' | 'attendance' | 'startDate' | 'endDate'>
  >,
  event: { startDate: string | null; endDate: string | null }
): Set<string> {
  const userIds = new Set<string>()
  if (event.startDate && event.endDate) {
    for (const rsvp of rsvps) {
      if (attendedDates(rsvp, event.startDate, event.endDate).includes(date)) {
        userIds.add(rsvp.userId)
      }
    }
  }
  return userIds
}

/**
 * The upcoming assignments whose holder isn't attending that day — chores
 * that won't get done unless someone else takes them over. These flag their
 * chips and feed the reassign nudge.
 *
 * Days before `today` are history and never stale. `rsvps` must be the
 * attending ones only.
 */
export function staleAssignmentIds(
  assignments: ReadonlyArray<
    Pick<PoolChoreAssignment, 'id' | 'userId' | 'date'>
  >,
  rsvps: ReadonlyArray<
    Pick<PoolRsvp, 'userId' | 'attendance' | 'startDate' | 'endDate'>
  >,
  event: { startDate: string; endDate: string },
  today: string
): Set<string> {
  const attendedByUser = new Map<string, string[]>()
  for (const rsvp of rsvps) {
    attendedByUser.set(
      rsvp.userId,
      attendedDates(rsvp, event.startDate, event.endDate)
    )
  }

  const stale = new Set<string>()
  for (const a of assignments) {
    if (a.date < today) continue
    if (!attendedByUser.get(a.userId)?.includes(a.date)) {
      stale.add(a.id)
    }
  }
  return stale
}

export function shouldSuggestAutofill(
  chores: ReadonlyArray<Pick<PoolChore, 'peoplePerDay'>>,
  dateCount: number,
  assignmentCount: number
): boolean {
  const seatsPerDay = chores.reduce((sum, c) => sum + c.peoplePerDay, 0)
  const totalSeats = seatsPerDay * dateCount
  return assignmentCount * 2 < totalSeats
}
