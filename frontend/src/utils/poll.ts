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

export function formatPollDeadline(deadline: string): string {
  const now = new Date()
  const diff = new Date(deadline).getTime() - now.getTime()

  if (diff <= 0) return 'Deadline passed'

  const days = Math.floor(diff / (1000 * 60 * 60 * 24))
  const hours = Math.floor((diff % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60))

  if (days > 0) return `${days}d ${hours}h remaining`
  if (hours > 0) return `${hours}h remaining`
  const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60))
  return `${minutes}m remaining`
}
