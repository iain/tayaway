import { DateTime } from 'luxon'
import type { DatePollStatus } from '@/types/pool'

interface PollLike {
  status: DatePollStatus
}

export function isPollOpen(poll: PollLike | null | undefined): boolean {
  return poll?.status === 'open'
}

export function isPollExpired(poll: PollLike | null | undefined): boolean {
  return poll?.status === 'expired'
}

export function isPollResolved(poll: PollLike | null | undefined): boolean {
  return poll?.status === 'resolved'
}

// "active" = poll exists and is not yet resolved (open or expired)
export function isPollActive(poll: PollLike | null | undefined): boolean {
  return poll != null && poll.status !== 'resolved'
}

// can be closed = active + has at least one date range
export function canClosePoll(
  poll: PollLike | null | undefined,
  dateRangeCount: number
): boolean {
  return isPollActive(poll) && dateRangeCount > 0
}

interface RankableDateRange {
  startDate: string
  voteSummary: { yes: number; preferably_not: number; no: number }
}

/**
 * Order date options best-first: most yes votes, then fewest hard objections,
 * then fewest "preferably not", with chronological order as the final
 * tiebreak so an all-square poll still reads as a calendar.
 */
export function rankDateRanges<T extends RankableDateRange>(
  ranges: readonly T[]
): T[] {
  return [...ranges].sort((a, b) => {
    if (a.voteSummary.yes !== b.voteSummary.yes) {
      return b.voteSummary.yes - a.voteSummary.yes
    }
    if (a.voteSummary.no !== b.voteSummary.no) {
      return a.voteSummary.no - b.voteSummary.no
    }
    if (a.voteSummary.preferably_not !== b.voteSummary.preferably_not) {
      return a.voteSummary.preferably_not - b.voteSummary.preferably_not
    }
    return a.startDate.localeCompare(b.startDate)
  })
}

export function formatPollDeadline(
  deadline: string,
  now: number = Date.now()
): string {
  const remaining = DateTime.fromISO(deadline).diff(DateTime.fromMillis(now))

  if (remaining.toMillis() <= 0) return 'Deadline passed'

  const { days, hours, minutes } = remaining.shiftTo('days', 'hours', 'minutes')

  if (days > 0) return `${days}d ${Math.floor(hours)}h remaining`
  if (hours >= 1) return `${Math.floor(hours)}h remaining`
  return `${Math.floor(minutes)}m remaining`
}

/**
 * The default poll deadline the "open poll" form pre-fills: a week out at 23:59
 * local, formatted for an `<input type="datetime-local">` ("YYYY-MM-DDTHH:mm").
 */
export function defaultPollDeadline(now: number = Date.now()): string {
  return DateTime.fromMillis(now)
    .plus({ days: 7 })
    .set({ hour: 23, minute: 59, second: 0, millisecond: 0 })
    .toFormat("yyyy-MM-dd'T'HH:mm")
}
