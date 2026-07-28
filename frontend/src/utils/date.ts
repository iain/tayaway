import { DateTime, Duration, Info, Interval } from 'luxon'

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
 * Whole days from `startDate` to `endDate` (both "YYYY-MM-DD") — e.g. the number
 * of nights in a stay. UTC-anchored so the count stays exact and integral across
 * DST transitions.
 */
export function daysBetween(startDate: string, endDate: string): number {
  const start = DateTime.fromISO(startDate, { zone: 'utc' })
  const end = DateTime.fromISO(endDate, { zone: 'utc' })
  return end.diff(start, 'days').days
}

/**
 * Milliseconds from `now` (epoch ms) until the next local midnight — the delay a
 * reactive "today" clock waits before rolling over. Defaults to the current
 * clock.
 */
export function msUntilNextLocalMidnight(now: number = Date.now()): number {
  return (
    DateTime.fromMillis(now).plus({ days: 1 }).startOf('day').toMillis() - now
  )
}

/** Whether the instant `iso` lies strictly before `now` (epoch ms). */
export function isPastIso(iso: string, now: number = Date.now()): boolean {
  return DateTime.fromISO(iso).toMillis() < now
}

/** Whether the instant `iso` lies strictly after `now` (epoch ms). */
export function isFutureIso(iso: string, now: number = Date.now()): boolean {
  return DateTime.fromISO(iso).toMillis() > now
}

/** Add `hours` to an ISO timestamp, returning a UTC ISO-8601 string. */
export function addHours(iso: string, hours: number): string {
  return DateTime.fromISO(iso).plus({ hours }).toUTC().toISO()!
}

/**
 * The instant behind a `<input type="datetime-local">` value ("YYYY-MM-DDTHH:mm",
 * read in the local zone) as a UTC ISO-8601 string ready to send to the server.
 */
export function datetimeLocalToIso(value: string): string {
  return DateTime.fromISO(value).toUTC().toISO()!
}

/**
 * "Mon, Jan 1, 2024" — full display date (weekday + month + day + year).
 * Pass `useLocale().value` from a Vue component so this honors the user's
 * chosen date/time format instead of always rendering the same locale for
 * everyone.
 */
export function formatDateDisplay(dateString: string, locale?: string): string {
  return parseDate(dateString, locale).toLocaleString(
    DateTime.DATE_MED_WITH_WEEKDAY
  )
}

/** "Sat, Mar 10" — weekday + date, the chore-roster day label */
export function formatDayHeader(dateString: string, locale?: string): string {
  return parseDate(dateString, locale).toLocaleString({
    weekday: 'short',
    month: 'short',
    day: 'numeric',
  })
}

/** "Jan 1, 2024" — date without weekday */
export function formatDateShort(dateString: string, locale?: string): string {
  return parseDate(dateString, locale).toLocaleString(DateTime.DATE_MED)
}

/**
 * "Mon 10" — short weekday + day-of-month, the compact chore-grid column header
 * (the month lives in the surrounding grid, so it's dropped here).
 */
export function formatWeekdayDay(dateString: string, locale?: string): string {
  const day = parseDate(dateString, locale)
  return `${day.toLocaleString({ weekday: 'short' })} ${day.day}`
}

/** "Jan 1 – 5, 2024" or "Jan 1, 2024 – Feb 3, 2024" — smart date range */
export function formatDateRange(
  startDate: string,
  endDate: string,
  locale?: string
): string {
  return Interval.fromDateTimes(
    parseDate(startDate, locale),
    parseDate(endDate, locale)
  ).toLocaleString(DateTime.DATE_MED)
}

/**
 * Localized birthday display (e.g. "Feb 27, 2024" or "27 feb 2024"). The month
 * is always spelled out: an all-numeric rendering reads differently in DD/MM
 * and MM/DD locales, and a birthday is exactly the field where that ambiguity
 * hides a wrongly-entered date.
 */
export function formatBirthday(dateString: string, locale?: string): string {
  return parseDate(dateString, locale).toLocaleString(DateTime.DATE_MED)
}

/**
 * "Jan 1, 11:30" — date + time, used for the absolute tooltip on
 * `<TimeAnchor>` and any other place that wants to expose the exact moment
 * behind a relative label. Pass `useLocale().value` from a Vue component so
 * a future user-chosen locale propagates here too.
 */
export function formatDateTime(isoString: string, locale?: string): string {
  return DateTime.fromISO(isoString, { locale }).toLocaleString({
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  })
}

/** "2:30 PM" / "14:30" — clock time only, in the viewer's locale. */
export function formatClockTime(isoString: string, locale?: string): string {
  return DateTime.fromISO(isoString, { locale }).toLocaleString({
    hour: '2-digit',
    minute: '2-digit',
  })
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
  const diffMs = DateTime.fromMillis(now).diff(date).toMillis()
  const isPast = diffMs >= 0
  const elapsed = Duration.fromMillis(Math.abs(diffMs))

  const minutes = Math.floor(elapsed.as('minutes'))
  const hours = Math.floor(elapsed.as('hours'))
  const days = Math.floor(elapsed.as('days'))
  const weeks = Math.floor(elapsed.as('weeks'))

  if (minutes < 1) return 'just now'

  let unit: string
  if (minutes < 60) unit = `${minutes}m`
  else if (hours < 24) unit = `${hours}h`
  else if (days < 7) unit = `${days}d`
  else if (weeks < 4) unit = `${weeks}w`
  else return date.toLocaleString(DateTime.DATE_MED)

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

  return date.toLocaleString(DateTime.DATE_MED)
}

/** Localized month name (e.g. "January") */
export function getMonthName(month: number, locale?: string): string {
  return Info.months('long', { locale })[month]
}

/** One cell of a month-picker grid. */
export interface CalendarDay {
  /** The day-of-month number (1–31), for display. */
  dayOfMonth: number
  /** False for the leading/trailing days that spill in from adjacent months. */
  isCurrentMonth: boolean
  /** The day as "YYYY-MM-DD", the key everything else compares against. */
  dateString: string
}

/**
 * A fixed 6×7 month grid (42 cells) for a date picker, weeks starting Monday,
 * padded with the spill-over days of the adjacent months. `month` is 0-based to
 * match `Date`/`getMonth`. All days are local calendar days.
 */
export function monthGridDays(year: number, month: number): CalendarDay[] {
  const first = DateTime.local(year, month + 1, 1)
  // weekday is 1 (Mon) … 7 (Sun), so `weekday - 1` backs up to the Monday.
  const gridStart = first.minus({ days: first.weekday - 1 })
  return Array.from({ length: 42 }, (_, i) => {
    const day = gridStart.plus({ days: i })
    return {
      dayOfMonth: day.day,
      isCurrentMonth: day.month === month + 1,
      dateString: day.toISODate()!,
    }
  })
}

/**
 * The Monday that opens the week after the one containing the day *after*
 * `dateString` — the next fresh roster week. When that day is itself a Monday,
 * it jumps a full week rather than returning the same day.
 */
export function nextMondayAfter(dateString: string): string {
  const dayAfter = parseDate(dateString).plus({ days: 1 })
  // 8 - weekday lands on the following Monday (and on Monday input yields 7).
  return dayAfter.plus({ days: 8 - dayAfter.weekday }).toISODate()!
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
  const next = nextBirthdayOccurrence(birthday, today)
  if (!next) return formatBirthday(birthday, locale)

  const diffDays = Math.round(next.diff(today, 'days').days)
  if (diffDays === 0) return 'Today'
  if (diffDays === 1) return 'Tomorrow'
  if (diffDays > 7) return formatBirthday(birthday, locale)
  if (diffDays === 7) {
    // Seven days out lands on today's weekday, so a bare weekday name
    // would read as today.
    return `Next ${next.toLocaleString({ weekday: 'long' })}`
  }

  return next.toLocaleString({ weekday: 'long' })
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
