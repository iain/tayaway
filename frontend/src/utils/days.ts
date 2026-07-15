import type { PoolAttendance } from '@/types/pool'
import { attendanceDates, enumerateDates } from './event'

/** One event day joined with everyone present on it. */
export interface DaySummary {
  date: string
  /** Going members present this day, in attendance order. */
  userIds: string[]
  /** Going guests present this day. */
  guests: number
  /** Members plus guests — the number to cook and shop for. */
  headcount: number
  /** Members present this day but not the day before (first day: everyone). */
  arrivals: string[]
  /** Members present this day but not the day after (last day: everyone). */
  departures: string[]
}

type AttendanceLike = Pick<
  PoolAttendance,
  'userId' | 'guestId' | 'status' | 'days'
>

/**
 * Join every event day with who is there, resolved from the going
 * attendances (explicit day set → whole event). Arrivals and departures are
 * day-over-day set differences over member rows, so a come-and-go stay that
 * leaves and returns shows up in both lists more than once. Guest rows count
 * into `guests`/`headcount` for the day.
 */
export function daySummaries(
  attendances: readonly AttendanceLike[],
  event: { startDate: string | null; endDate: string | null }
): DaySummary[] {
  if (!event.startDate || !event.endDate) return []

  const memberDays = new Map<string, Set<string>>()
  const guestCountByDay = new Map<string, number>()
  for (const attendance of attendances) {
    const days = attendanceDates(attendance, event.startDate, event.endDate)
    if (attendance.userId) {
      memberDays.set(attendance.userId, new Set(days))
    } else {
      for (const day of days) {
        guestCountByDay.set(day, (guestCountByDay.get(day) ?? 0) + 1)
      }
    }
  }

  const dates = enumerateDates(event.startDate, event.endDate)
  return dates.map((date, i) => {
    const userIds: string[] = []
    const arrivals: string[] = []
    const departures: string[] = []
    for (const [userId, days] of memberDays) {
      if (!days.has(date)) continue
      userIds.push(userId)
      if (i === 0 || !days.has(dates[i - 1]!)) arrivals.push(userId)
      if (i === dates.length - 1 || !days.has(dates[i + 1]!)) {
        departures.push(userId)
      }
    }
    const guests = guestCountByDay.get(date) ?? 0
    return {
      date,
      userIds,
      guests,
      headcount: userIds.length + guests,
      arrivals,
      departures,
    }
  })
}
