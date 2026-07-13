import type { PoolRsvp } from '@/types/pool'
import { attendedDays, enumerateDates } from './event'

/** One event day joined with everyone present on it. */
export interface DaySummary {
  date: string
  /** Attending members present this day, in RSVP order. */
  userIds: string[]
  /** Total +1 guests brought along this day. */
  guests: number
  /** Members plus guests — the number to cook and shop for. */
  headcount: number
  /** Present this day but not the day before (first day: everyone). */
  arrivals: string[]
  /** Present this day but not the day after (last day: everyone). */
  departures: string[]
}

type RsvpLike = Pick<
  PoolRsvp,
  'userId' | 'attending' | 'attendance' | 'startDate' | 'endDate'
>

/**
 * Join every event day with who is there, resolved from the attending RSVPs
 * via the usual precedence (day set → legacy range → whole event). Arrivals
 * and departures are day-over-day set differences, so a come-and-go RSVP
 * that leaves and returns shows up in both lists more than once.
 */
export function daySummaries(
  rsvps: readonly RsvpLike[],
  event: { startDate: string | null; endDate: string | null }
): DaySummary[] {
  if (!event.startDate || !event.endDate) return []

  const guestsByUserDay = new Map<string, Map<string, number>>()
  for (const rsvp of rsvps) {
    if (!rsvp.attending) continue
    const days = attendedDays(rsvp, event.startDate, event.endDate)
    guestsByUserDay.set(
      rsvp.userId,
      new Map(days.map((d) => [d.date, d.plusOnes]))
    )
  }

  const dates = enumerateDates(event.startDate, event.endDate)
  return dates.map((date, i) => {
    const userIds: string[] = []
    let guests = 0
    const arrivals: string[] = []
    const departures: string[] = []
    for (const [userId, dayGuests] of guestsByUserDay) {
      if (!dayGuests.has(date)) continue
      userIds.push(userId)
      guests += dayGuests.get(date) ?? 0
      if (i === 0 || !dayGuests.has(dates[i - 1]!)) arrivals.push(userId)
      if (i === dates.length - 1 || !dayGuests.has(dates[i + 1]!)) {
        departures.push(userId)
      }
    }
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
