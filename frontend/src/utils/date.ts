function parseDate(dateString: string): Date {
  const [year, month, day] = dateString.split('-').map(Number) as [
    number,
    number,
    number,
  ]
  return new Date(year, month - 1, day)
}

/**
 * Add (or subtract, with a negative `days`) whole days to a "YYYY-MM-DD"
 * string, returning the same format. Pure calendar arithmetic — zone-
 * independent — and the single home for it (used by useCalendar and the
 * timezone-aware chore reckoning alike).
 */
export function addDays(dateString: string, days: number): string {
  const date = parseDate(dateString)
  date.setDate(date.getDate() + days)
  const year = date.getFullYear()
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')
  return `${year}-${month}-${day}`
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

/**
 * "Jan 1, 11:30" — date + time, used for the absolute tooltip on
 * `<TimeAnchor>` and any other place that wants to expose the exact moment
 * behind a relative label. Pass `useLocale().value` from a Vue component so
 * a future user-chosen locale propagates here too.
 */
export function formatDateTime(isoString: string, locale?: string): string {
  return new Date(isoString).toLocaleDateString(locale, {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}

/**
 * Compact relative time: "just now", "5m ago", "2h ago", "3d ago", "2w ago",
 * "in 5m", "in 3d", or a fallback short date for anything older than four
 * weeks. The Tayaway time voice — always compact units (`m`/`h`/`d`/`w`),
 * never long forms, anchored to a verb by the caller ("Sent 3h ago" rather
 * than "Sent three hours ago").
 *
 * Accepts an optional `now` so consumers with a reactive clock (the shared
 * minute ticker behind `useRelativeTime`) can pass it in and have the
 * output update as time passes. Defaults to Date.now() for one-shot
 * callers.
 */
export function formatRelativeDate(
  isoString: string,
  now: number = Date.now()
): string {
  const date = new Date(isoString)
  const diffMs = now - date.getTime()
  const absMs = Math.abs(diffMs)
  const isPast = diffMs >= 0

  const diffMinutes = Math.floor(absMs / 60_000)
  const diffHours = Math.floor(absMs / 3_600_000)
  const diffDays = Math.floor(absMs / 86_400_000)
  const diffWeeks = Math.floor(absMs / (7 * 86_400_000))

  if (diffMinutes < 1) return 'just now'

  let unit: string
  if (diffMinutes < 60) unit = `${diffMinutes}m`
  else if (diffHours < 24) unit = `${diffHours}h`
  else if (diffDays < 7) unit = `${diffDays}d`
  else if (diffWeeks < 4) unit = `${diffWeeks}w`
  else
    return date.toLocaleDateString(undefined, {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
    })

  return isPast ? `${unit} ago` : `in ${unit}`
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
