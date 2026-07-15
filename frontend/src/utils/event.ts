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
