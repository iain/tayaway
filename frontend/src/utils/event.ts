interface EventLike {
  startDate: string | null
  endDate: string | null
}

export function eventHasDates(event: EventLike | null | undefined): boolean {
  return event != null && event.startDate != null && event.endDate != null
}

export function eventIsPlanning(event: EventLike | null | undefined): boolean {
  return event != null && event.startDate == null
}

export function eventIsUpcoming(
  event: EventLike | null | undefined,
  today = new Date().toISOString().slice(0, 10)
): boolean {
  return event != null && event.startDate != null && event.startDate >= today
}

export function eventIsPast(
  event: EventLike | null | undefined,
  today = new Date().toISOString().slice(0, 10)
): boolean {
  return event != null && event.startDate != null && event.startDate < today
}
