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
