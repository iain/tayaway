import { addDays, daysBetween, localIsoDate } from './date'

interface EventLike {
  startDate: string | null
  endDate: string | null
}

export function countNights(startDate: string, endDate: string): number {
  return daysBetween(startDate, endDate)
}

export function countDays(startDate: string, endDate: string): number {
  return countNights(startDate, endDate) + 1
}

/**
 * Expand an inclusive ISO date range into the list of YYYY-MM-DD strings it
 * covers. Steps by whole calendar days, so it's DST-proof.
 */
export function enumerateDates(startDate: string, endDate: string): string[] {
  const dates: string[] = []
  for (let date = startDate; date <= endDate; date = addDays(date, 1)) {
    dates.push(date)
  }
  return dates
}

/**
 * The concrete ISO days an attendance row covers, resolved against its
 * event: the explicit `days` set when present, otherwise the whole event.
 * Non-going rows cover nothing — days carry meaning only when going
 * (doc/attendances.md).
 */
export function attendanceDates(
  attendance: { status: string; days: string[] | null },
  eventStartDate: string,
  eventEndDate: string
): string[] {
  if (attendance.status !== 'going') return []
  return attendance.days ?? enumerateDates(eventStartDate, eventEndDate)
}

/**
 * A raw attendance day as it arrives over the wire (or from the IndexedDB
 * cache): a bare ISO date string for a guest-free day, or an object carrying
 * that day's `plusOnes` guest count. Both shapes coexist — old clients and
 * pre-plus-ones rows use the string form.
 */
export type AttendanceEntry = string | { date: string; plusOnes: number }

/** A normalized attendance day: an ISO date plus its guest count. */
export interface AttendanceDay {
  date: string
  plusOnes: number
}

interface AttendanceLike {
  attendance?: AttendanceEntry[] | null
  startDate: string | null
  endDate: string | null
}

function normalizeAttendanceEntry(entry: AttendanceEntry): AttendanceDay {
  return typeof entry === 'string'
    ? { date: entry, plusOnes: 0 }
    : { date: entry.date, plusOnes: entry.plusOnes ?? 0 }
}

/**
 * The days an RSVP covers, each with its guest count. An explicit `attendance`
 * day set wins; otherwise the contiguous startDate..endDate range; otherwise
 * the whole event. Range- and whole-event RSVPs carry no guests. Mirrors
 * Rsvp#effective_attendance on the backend.
 */
export function attendedDays(
  rsvp: AttendanceLike,
  eventStartDate: string,
  eventEndDate: string
): AttendanceDay[] {
  if (rsvp.attendance && rsvp.attendance.length > 0)
    return rsvp.attendance.map(normalizeAttendanceEntry)
  const range =
    rsvp.startDate && rsvp.endDate
      ? enumerateDates(rsvp.startDate, rsvp.endDate)
      : enumerateDates(eventStartDate, eventEndDate)
  return range.map((date) => ({ date, plusOnes: 0 }))
}

/**
 * The set of ISO days an RSVP covers, dropping guest counts. Mirrors
 * Rsvp#effective_dates on the backend.
 */
export function attendedDates(
  rsvp: AttendanceLike,
  eventStartDate: string,
  eventEndDate: string
): string[] {
  return attendedDays(rsvp, eventStartDate, eventEndDate).map((d) => d.date)
}

export function eventHasDates(event: EventLike | null | undefined): boolean {
  return event != null && event.startDate != null && event.endDate != null
}

export function eventIsPlanning(event: EventLike | null | undefined): boolean {
  return event != null && event.startDate == null
}

export function eventIsCurrent(
  event: EventLike | null | undefined,
  today = localIsoDate()
): boolean {
  return (
    event != null &&
    event.startDate != null &&
    event.endDate != null &&
    event.startDate <= today &&
    event.endDate >= today
  )
}

export function eventIsUpcoming(
  event: EventLike | null | undefined,
  today = localIsoDate()
): boolean {
  return event != null && event.startDate != null && event.startDate > today
}

export function eventIsPast(
  event: EventLike | null | undefined,
  today = localIsoDate()
): boolean {
  return (
    event != null &&
    event.startDate != null &&
    event.startDate < today &&
    (event.endDate == null || event.endDate < today)
  )
}
