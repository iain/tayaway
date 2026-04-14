function parseDate(dateString: string): Date {
  const [year, month, day] = dateString.split('-').map(Number) as [
    number,
    number,
    number,
  ]
  return new Date(year, month - 1, day)
}

/** "Mon, Jan 1, 2024" — full display date (weekday + month + day + year) */
export function formatDateDisplay(dateString: string): string {
  const date = parseDate(dateString)
  return date.toLocaleDateString(undefined, {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  })
}

/** "Jan 1, 2024" — date without weekday */
export function formatDateShort(dateString: string): string {
  const date = parseDate(dateString)
  return date.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  })
}

/** "Jan 1 – 5, 2024" or "Jan 1, 2024 – Feb 3, 2024" — smart date range */
export function formatDateRange(startDate: string, endDate: string): string {
  const start = parseDate(startDate)
  const end = parseDate(endDate)
  const opts: Intl.DateTimeFormatOptions = { month: 'short', day: 'numeric' }

  if (start.getFullYear() === end.getFullYear()) {
    if (start.getMonth() === end.getMonth()) {
      return `${start.toLocaleDateString(undefined, opts)} \u2013 ${end.getDate()}, ${end.getFullYear()}`
    }
    return `${start.toLocaleDateString(undefined, opts)} \u2013 ${end.toLocaleDateString(undefined, opts)}, ${end.getFullYear()}`
  }

  return `${start.toLocaleDateString(undefined, { ...opts, year: 'numeric' })} \u2013 ${end.toLocaleDateString(undefined, { ...opts, year: 'numeric' })}`
}

/** Localized birthday display (e.g. "27/02/2024") */
export function formatBirthday(dateString: string): string {
  const date = parseDate(dateString)
  return date.toLocaleDateString(undefined, {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
  })
}

/** "Jan 1, 11:30" — date + time (for settlement timestamps) */
export function formatDateTime(isoString: string): string {
  return new Date(isoString).toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}

/**
 * "Just now", "5m ago", "2h ago", "3d ago", or fallback to short date.
 *
 * Accepts an optional `now` so consumers with a reactive clock (e.g. the
 * layout's minute ticker) can pass it in and have the output update as
 * time passes. Defaults to Date.now() for one-shot callers.
 */
export function formatRelativeDate(
  isoString: string,
  now: number = Date.now()
): string {
  const date = new Date(isoString)
  const diffMs = now - date.getTime()
  const diffMinutes = Math.floor(diffMs / 60000)
  const diffHours = Math.floor(diffMs / 3600000)
  const diffDays = Math.floor(diffMs / 86400000)

  if (diffMinutes < 1) return 'Just now'
  if (diffMinutes < 60) return `${diffMinutes}m ago`
  if (diffHours < 24) return `${diffHours}h ago`
  if (diffDays < 30) return `${diffDays}d ago`
  return date.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  })
}

/** "Past deadline", "Due today", "Due tomorrow", "Due in 3 days", or short date */
export function formatDeadline(deadline: string): string {
  const date = new Date(deadline)
  const now = new Date()
  const diffMs = date.getTime() - now.getTime()
  const diffDays = Math.ceil(diffMs / (1000 * 60 * 60 * 24))

  if (diffDays < 0) return 'Past deadline'
  if (diffDays === 0) return 'Due today'
  if (diffDays === 1) return 'Due tomorrow'
  if (diffDays <= 7) return `Due in ${diffDays} days`

  return date.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  })
}

/** Localized month name (e.g. "January") */
export function getMonthName(month: number): string {
  const date = new Date(2024, month, 1)
  return date.toLocaleDateString(undefined, { month: 'long' })
}
