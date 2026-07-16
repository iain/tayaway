import type {
  PoolAttendance,
  PoolChore,
  PoolChoreAssignment,
  PoolMember,
} from '@/types/pool'
import type { HydratedAttendance } from '@/composables/useHydratedEvent'
import { attendanceDates } from '@/utils/event'
import { wallClockToEpoch } from '@/utils/timezone'

type AttendanceLike = Pick<PoolAttendance, 'id' | 'userId' | 'status' | 'days'>

type AssignmentHolder = Pick<PoolChoreAssignment, 'attendanceId' | 'userId'>

// Attended dates per going attendance — member and guest rows alike, since
// assignments are keyed by the attendance behind the holder.
function attendedDates(
  attendances: readonly AttendanceLike[],
  event: { startDate: string; endDate: string }
): Map<string, string[]> {
  const byAttendance = new Map<string, string[]>()
  for (const attendance of attendances) {
    const dates = attendanceDates(attendance, event.startDate, event.endDate)
    if (dates.length > 0) byAttendance.set(attendance.id, dates)
  }
  return byAttendance
}

// Legacy rows predating the attendance link resolve their holder through the
// mirrored userId; gone once those rows are backfilled and user_id retires.
function attendanceIdByUser(
  attendances: readonly AttendanceLike[]
): Map<string, string> {
  const byUser = new Map<string, string>()
  for (const attendance of attendances) {
    if (attendance.userId) byUser.set(attendance.userId, attendance.id)
  }
  return byUser
}

/** The attendance id behind an assignment's holder, via the legacy-userId
 *  fallback when the row predates the attendance link. */
export function holderAttendanceId(
  assignment: AssignmentHolder,
  byUser: Map<string, string>
): string | null {
  if (assignment.attendanceId) return assignment.attendanceId
  if (assignment.userId) return byUser.get(assignment.userId) ?? null
  return null
}

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
 * The person behind one chore assignment, resolved through its attendance's
 * attendee. Legacy rows without an attendance link fall back to the mirrored
 * userId and the member map.
 */
export interface AssignmentPerson {
  name: string
  isGuest: boolean
  /** Member holders: their userId, for "is this me" emphasis. Null for
   *  guests and unresolvable rows. */
  userId: string | null
}

export function assignmentPerson(
  assignment: AssignmentHolder,
  attendanceById: Map<string, HydratedAttendance>,
  memberByUserId: Map<string, PoolMember>
): AssignmentPerson {
  const attendance = assignment.attendanceId
    ? attendanceById.get(assignment.attendanceId)
    : undefined
  if (attendance) {
    return {
      name: attendance.attendee.name,
      isGuest: attendance.attendee.isGuest,
      userId: attendance.attendee.member?.userId ?? null,
    }
  }

  const member = assignment.userId
    ? memberByUserId.get(assignment.userId)
    : undefined
  if (member) {
    return {
      name: member.name ?? member.email.split('@')[0] ?? member.email,
      isGuest: false,
      userId: assignment.userId,
    }
  }
  return { name: '?', isGuest: false, userId: assignment.userId }
}

/**
 * The attendances that can take a chore on one specific day: going, covering
 * that date — members and guests alike — the eligibility set for assigning
 * (or reassigning) that day's chores, mirroring the backend autofill's
 * availability map for a single date.
 */
export function assignableAttendancesOn(
  date: string,
  attendances: readonly HydratedAttendance[],
  event: { startDate: string | null; endDate: string | null }
): HydratedAttendance[] {
  if (!event.startDate || !event.endDate) return []
  const start = event.startDate
  const end = event.endDate
  return attendances.filter((a) =>
    attendanceDates(a, start, end).includes(date)
  )
}

/**
 * The upcoming assignments whose holder isn't attending that day — chores
 * that won't get done unless someone else takes them over. These flag their
 * chips and feed the reassign nudge. An assignment is stale iff its
 * attendance's days no longer cover its date.
 *
 * Days before `today` are history and never stale.
 */
export function staleAssignmentIds(
  assignments: ReadonlyArray<
    Pick<PoolChoreAssignment, 'id' | 'attendanceId' | 'userId' | 'date'>
  >,
  attendances: readonly AttendanceLike[],
  event: { startDate: string; endDate: string },
  today: string
): Set<string> {
  const dates = attendedDates(attendances, event)
  const byUser = attendanceIdByUser(attendances)

  const stale = new Set<string>()
  for (const a of assignments) {
    if (a.date < today) continue
    const attendanceId = holderAttendanceId(a, byUser)
    const covered =
      attendanceId !== null && dates.get(attendanceId)?.includes(a.date)
    if (!covered) stale.add(a.id)
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
