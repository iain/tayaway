import type { PoolAttendance } from '@/types/pool'
import { attendanceDates, enumerateDates } from './event'

type AttendanceLike = Pick<PoolAttendance, 'status' | 'days'>

/** One event day joined with everyone present on it. */
export interface DaySummary<T> {
  date: string
  /** Going attendances present this day — members and guests alike. */
  present: T[]
  /** Everyone present — the number to cook and shop for. */
  headcount: number
  /** Present this day but not the day before (first day: everyone). */
  arrivals: T[]
  /** Present this day but not the day after (last day: everyone). */
  departures: T[]
}

/**
 * Join every event day with who is there, resolved from the going
 * attendances (explicit day set → whole event). Arrivals and departures are
 * day-over-day set differences, so a come-and-go stay that leaves and
 * returns shows up in both lists more than once. Rows pass through as given
 * — callers resolve them to attendees (names, member/guest) themselves.
 */
export function daySummaries<T extends AttendanceLike>(
  attendances: readonly T[],
  event: { startDate: string | null; endDate: string | null }
): DaySummary<T>[] {
  if (!event.startDate || !event.endDate) return []

  const coverage = attendances.map((attendance) => ({
    attendance,
    days: new Set(
      attendanceDates(attendance, event.startDate!, event.endDate!)
    ),
  }))

  const dates = enumerateDates(event.startDate, event.endDate)
  return dates.map((date, i) => {
    const present: T[] = []
    const arrivals: T[] = []
    const departures: T[] = []
    for (const { attendance, days } of coverage) {
      if (!days.has(date)) continue
      present.push(attendance)
      if (i === 0 || !days.has(dates[i - 1]!)) arrivals.push(attendance)
      if (i === dates.length - 1 || !days.has(dates[i + 1]!)) {
        departures.push(attendance)
      }
    }
    return { date, present, headcount: present.length, arrivals, departures }
  })
}
