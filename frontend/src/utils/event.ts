interface EventLike {
  startDate: string | null
  endDate: string | null
}

export function countNights(startDate: string, endDate: string): number {
  return (
    (new Date(endDate).getTime() - new Date(startDate).getTime()) / 86_400_000
  )
}

export function countDays(startDate: string, endDate: string): number {
  return countNights(startDate, endDate) + 1
}

/**
 * Expand an inclusive ISO date range into the list of YYYY-MM-DD strings it
 * covers. Anchored to UTC midnight so day stepping is DST-proof.
 */
export function enumerateDates(startDate: string, endDate: string): string[] {
  const dates: string[] = []
  const start = new Date(`${startDate}T00:00:00Z`).getTime()
  const end = new Date(`${endDate}T00:00:00Z`).getTime()
  for (let t = start; t <= end; t += 86_400_000) {
    dates.push(new Date(t).toISOString().slice(0, 10))
  }
  return dates
}

interface AttendanceLike {
  attendance?: string[] | null
  startDate: string | null
  endDate: string | null
}

/**
 * The set of ISO days an RSVP covers. An explicit `attendance` day set wins;
 * otherwise the contiguous startDate..endDate range; otherwise the whole event.
 * Mirrors Rsvp#effective_dates on the backend.
 */
export function attendedDates(
  rsvp: AttendanceLike,
  eventStartDate: string,
  eventEndDate: string
): string[] {
  if (rsvp.attendance && rsvp.attendance.length > 0) return rsvp.attendance
  if (rsvp.startDate && rsvp.endDate)
    return enumerateDates(rsvp.startDate, rsvp.endDate)
  return enumerateDates(eventStartDate, eventEndDate)
}

export function eventHasDates(event: EventLike | null | undefined): boolean {
  return event != null && event.startDate != null && event.endDate != null
}

export function eventIsPlanning(event: EventLike | null | undefined): boolean {
  return event != null && event.startDate == null
}

export function eventIsCurrent(
  event: EventLike | null | undefined,
  today = new Date().toISOString().slice(0, 10)
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
  today = new Date().toISOString().slice(0, 10)
): boolean {
  return event != null && event.startDate != null && event.startDate > today
}

export function eventIsPast(
  event: EventLike | null | undefined,
  today = new Date().toISOString().slice(0, 10)
): boolean {
  return (
    event != null &&
    event.startDate != null &&
    event.startDate < today &&
    (event.endDate == null || event.endDate < today)
  )
}
