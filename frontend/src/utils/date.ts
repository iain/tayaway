import { DateTime, Duration } from 'luxon'

// How far ahead the dashboard looks for "upcoming" birthdays — the horizon over
// which a birthday counts as "loading". Shared so the classification window
// (HomePage) and the countdown's loading-progress denominator stay in lockstep;
// widen it in one place and both follow.
export const UPCOMING_BIRTHDAY_WINDOW_DAYS = 7

function parseDate(dateString: string, locale?: string): DateTime {
  return DateTime.fromISO(dateString, { locale })
}

/**
 * The current instant as an ISO-8601 UTC string with milliseconds
 * ("2026-07-15T10:10:34.123Z") — byte-identical to `new Date().toISOString()`.
 * The single home for the "now" timestamps stores stamp optimistically onto
 * records (paidAt, readAt, updatedAt, …) before the server confirms.
 */
export function nowIso(): string {
  // A live clock is always a valid DateTime, so toISO() never returns null.
  return DateTime.utc().toISO()!
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
  return parseDate(dateString, locale).toLocaleString({
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
  if (diffDays === 1) return 'Tomorrow'
  if (diffDays > 7) return formatBirthday(birthday, locale)
  if (diffDays === 7) {
    // Seven days out lands on today's weekday, so a bare weekday name
    // would read as today.
    return `Next ${next.toFormat('cccc')}`
  }

  return next.toFormat('cccc')
}

/**
 * Next occurrence of a birthday (only the month/day of `birthday` matter) on
 * or after `today`, or null if the date can't be parsed or applied. Guards the
 * Feb-29-on-a-non-leap-year overflow (Luxon rolls Feb 29 → Mar 1). The single
 * home for the "when is their next birthday" rolling rule, shared by the
 * countdown and the days-until reckoning.
 */
function nextBirthdayOccurrence(
  birthday: string,
  today: DateTime
): DateTime | null {
  const stored = parseDate(birthday)
  if (!stored.isValid) return null
  const next = today.set({ month: stored.month, day: stored.day })
  if (!next.isValid) return null
  return next < today ? next.plus({ years: 1 }) : next
}

/**
 * Whole calendar days from today (local) to a member's next birthday, or null
 * if `birthday` is absent/unparseable. Comparison runs in whole calendar days
 * regardless of time-of-day. `now` defaults to the current clock; pass one in
 * to pin it (tests, or to share a single "now" across a batch).
 */
export function daysUntilBirthday(
  birthday: string | null,
  now: number = Date.now()
): number | null {
  if (!birthday) return null
  const today = DateTime.fromMillis(now).startOf('day')
  const next = nextBirthdayOccurrence(birthday, today)
  return next ? Math.round(next.diff(today, 'days').days) : null
}

export interface BirthdayCountdown {
  /** Preformatted remaining time, e.g. "5d 02h 29m 15s" or "02h 29m 15s". */
  text: string
  /** Loading progress toward the birthday, 0–100 (whole percent). */
  percent: number
}

/**
 * Live countdown from `now` (epoch ms) to a birthday's next arrival at local
 * midnight, returned as display-ready primitives so callers never touch Luxon:
 * a preformatted `text` and a 0–100 `percent` of the way through the upcoming
 * window. Returns null when `birthday` is unparseable (see
 * `nextBirthdayOccurrence`). Clamps at zero rather than going negative, so the
 * final tick before midnight reads all-zeroes and the bar sits at 100% until
 * the dashboard reclassifies the person into today's celebrations.
 */
export function getBirthdayCountdown(
  birthday: string,
  now: number
): BirthdayCountdown | null {
  const current = DateTime.fromMillis(now)
  const target = nextBirthdayOccurrence(birthday, current.startOf('day'))
  if (!target) return null

  const elapsed = target.diff(current, ['days', 'hours', 'minutes', 'seconds'])
  const remaining = elapsed.toMillis() > 0 ? elapsed : Duration.fromMillis(0)

  // Luxon floors the fractional second for us. A single-letter token is
  // unpadded, a doubled one zero-pads: we leave the largest shown unit unpadded
  // (no leading zero on the number you read first) and zero-pad the smaller
  // units so their width stays stable as they tick — a digital-timer look. The
  // days segment is dropped under a day so it never reads "0d".
  const text =
    remaining.as('days') >= 1
      ? remaining.toFormat("d'd' hh'h' mm'm' ss's'")
      : remaining.toFormat("h'h' mm'm' ss's'")

  const windowSeconds = Duration.fromObject({
    days: UPCOMING_BIRTHDAY_WINDOW_DAYS,
  }).as('seconds')
  const loaded = 1 - remaining.as('seconds') / windowSeconds
  const percent = Math.min(100, Math.max(0, Math.round(loaded * 100)))

  return { text, percent }
}
