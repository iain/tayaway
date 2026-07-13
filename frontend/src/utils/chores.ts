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

export interface AttendanceDrift {
  /** Today-onward assignments whose assignee isn't attending that day. */
  staleAssignmentIds: Set<string>
  /** Attendees with remaining days but no upcoming assignment anywhere. */
  idleUserIds: string[]
}

/**
 * How far the roster has drifted from who is actually around: people who left
 * but still hold upcoming slots, and people who arrived (or extended) with
 * nothing to do. Both resolve with one re-run of auto-fill, which only touches
 * today onward — the page uses this to nudge exactly then.
 *
 * Days before `today` are history and never drift. `rsvps` must be the
 * attending ones only. Idle attendees are only reported while the roster has
 * upcoming assignments at all — an empty or wound-down roster is the plain
 * auto-fill nudge's territory, not drift.
 */
export function detectAttendanceDrift(
  assignments: ReadonlyArray<
    Pick<PoolChoreAssignment, 'id' | 'userId' | 'date'>
  >,
  rsvps: ReadonlyArray<
    Pick<PoolRsvp, 'userId' | 'attendance' | 'startDate' | 'endDate'>
  >,
  event: { startDate: string; endDate: string },
  today: string
): AttendanceDrift {
  const attendedByUser = new Map<string, string[]>()
  for (const rsvp of rsvps) {
    attendedByUser.set(
      rsvp.userId,
      attendedDates(rsvp, event.startDate, event.endDate)
    )
  }

  const staleAssignmentIds = new Set<string>()
  const upcomingAssignees = new Set<string>()
  for (const a of assignments) {
    if (a.date < today) continue
    upcomingAssignees.add(a.userId)
    if (!attendedByUser.get(a.userId)?.includes(a.date)) {
      staleAssignmentIds.add(a.id)
    }
  }

  const idleUserIds: string[] = []
  if (upcomingAssignees.size > 0) {
    for (const [userId, dates] of attendedByUser) {
      if (upcomingAssignees.has(userId)) continue
      if (dates.some((d) => d >= today)) idleUserIds.push(userId)
    }
  }

  return { staleAssignmentIds, idleUserIds }
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
