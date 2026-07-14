import { DateTime } from 'luxon'

function parseDate(dateString: string, locale?: string): DateTime {
  return DateTime.fromISO(dateString, { locale })
}

/**
 * A Date's calendar day as "YYYY-MM-DD", read from its LOCAL parts — the day
 * the user is actually living in. The single home for "today" everywhere
 * events and chore rosters classify against the current day.
 */
export function localIsoDate(date: Date = new Date()): string {
  return DateTime.fromJSDate(date).toISODate()!
}

/**
 * Add (or subtract, with a negative `days`) whole days to a "YYYY-MM-DD"
 * string, returning the same format. Pure calendar arithmetic — zone-
 * independent — and the single home for it (used by useCalendar and the
 * timezone-aware chore reckoning alike).
 */
export function addDays(dateString: string, days: number): string {
  return parseDate(dateString).plus({ days }).toISODate()!
}

/**
 * "Mon, Jan 1, 2024" — full display date (weekday + month + day + year).
 * Pass `useLocale().value` from a Vue component so this honors the user's
 * chosen date/time format instead of always rendering the same locale for
 * everyone.
 */
export function formatDateDisplay(dateString: string, locale?: string): string {
  return parseDate(dateString, locale).toFormat('ccc, LLL d, yyyy')
}

/** "Sat, Mar 10" — weekday + date, the chore-roster day label */
export function formatDayHeader(dateString: string, locale?: string): string {
  return parseDate(dateString, locale).toFormat('ccc d LLL')
}

/** "Jan 1, 2024" — date without weekday */
export function formatDateShort(dateString: string, locale?: string): string {
  return parseDate(dateString, locale).toFormat('LLL d, yyyy')
}

/** "Jan 1 – 5, 2024" or "Jan 1, 2024 – Feb 3, 2024" — smart date range */
export function formatDateRange(
  startDate: string,
  endDate: string,
  locale?: string
): string {
  const start = parseDate(startDate, locale)
  const end = parseDate(endDate, locale)

  if (start.year === end.year) {
    if (start.month === end.month) {
      return `${start.toFormat('LLL d')} \u2013 ${end.toFormat('d, yyyy')}`
    }
    return `${start.toFormat('LLL d')} \u2013 ${end.toFormat('LLL d, yyyy')}`
  }

  return `${start.toFormat('LLL d, yyyy')} \u2013 ${end.toFormat('LLL d, yyyy')}`
}

/** Localized birthday display (e.g. "27/02/2024" or "02/27/2024") */
export function formatBirthday(dateString: string, locale?: string): string {
  return parseDate(dateString, locale).toLocaleString(DateTime.DATE_SHORT)
}

/**
 * "Jan 1, 11:30" — date + time, used for the absolute tooltip on
 * `<TimeAnchor>` and any other place that wants to expose the exact moment
 * behind a relative label. Pass `useLocale().value` from a Vue component so
 * a future user-chosen locale propagates here too.
 */
export function formatDateTime(isoString: string, locale?: string): string {
  return DateTime.fromISO(isoString, { locale }).toFormat('LLL d, HH:mm')
}

/**
 * Compact relative time: "just now", "5m ago", "2h ago", "3d ago", "2w ago",
 * "in 5m", "in 3d", or a fallback short date for anything older than four
 * weeks. The Tayaway time voice — always compact units (`m`/`h`/`d`/`w`),
 * never long forms, anchored to a verb by the caller ("Sent 3h ago" rather
 * than "Sent three hours ago"). The compact units themselves aren't
 * localized (that's the app's fixed voice), but the date fallback honors
 * the passed locale.
 *
 * Accepts an optional `now` so consumers with a reactive clock (the shared
 * minute ticker behind `useRelativeTime`) can pass it in and have the
 * output update as time passes. Defaults to Date.now() for one-shot
 * callers.
 */
export function formatRelativeDate(
  isoString: string,
  now: number = Date.now(),
  locale?: string
): string {
  const date = DateTime.fromISO(isoString, { locale })
  const nowDt = DateTime.fromMillis(now)
  const diffMs = nowDt.diff(date).milliseconds
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
  else return date.toFormat('LLL d, yyyy')

  return isPast ? `${unit} ago` : `in ${unit}`
}

/** "Past deadline", "Due today", "Due tomorrow", "Due in 3 days", or short date */
export function formatDeadline(deadline: string, locale?: string): string {
  const date = DateTime.fromISO(deadline, { locale })
  const now = DateTime.local()
  const diffDays = Math.ceil(date.diff(now, 'days').days)

  if (diffDays < 0) return 'Past deadline'
  if (diffDays === 0) return 'Due today'
  if (diffDays === 1) return 'Due tomorrow'
  if (diffDays <= 7) return `Due in ${diffDays} days`

  return date.toFormat('LLL d, yyyy')
}

/** Localized month name (e.g. "January") */
export function getMonthName(month: number, locale?: string): string {
  return DateTime.local(2024, month + 1, 1, { locale }).toFormat('LLLL')
}

/**
 * Human label for a birthday's next occurrence: "Today", "Tomorrow", a
 * weekday name ("Tuesday") within the next week, or a plain formatted date
 * further out. `birthday` is a "YYYY-MM-DD" string where only month/day are
 * used — all comparisons run in local calendar days via Luxon, so no
 * timezone or time-of-day can shift the result by a day. Pass
 * `useLocale().value` so the weekday name and fallback date render in the
 * viewer's own language and format rather than one fixed locale for
 * everyone.
 */
export function formatUpcomingBirthday(
  birthday: string,
  locale?: string
): string {
  const today = DateTime.local()
    .startOf('day')
    .setLocale(locale ?? 'en-US')
  const stored = parseDate(birthday)
  let next = today.set({ month: stored.month, day: stored.day })
  if (next < today) next = next.plus({ years: 1 })

  const diffDays = next.diff(today, 'days').days
  if (diffDays === 0) return 'Today'
  if (diffDays > 7) return formatBirthday(birthday, locale)

  return next.toRelativeCalendar({ base: today }) ?? next.toFormat('cccc')
}
