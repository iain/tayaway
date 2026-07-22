// Timezone-aware helpers. The app reckons event-bound times (chore times,
// "today") in the *event's* zone, not the viewer's device zone, so a traveller
// sees the event's day and time. Luxon carries the zone through every
// conversion, including DST transitions.

import { DateTime } from 'luxon'

/** The viewer's own device zone, e.g. "Europe/Amsterdam". */
export function deviceTimezone(): string {
  return Intl.DateTimeFormat().resolvedOptions().timeZone
}

/**
 * An IANA id as a person would read it: "America/New_York" → "New York ·
 * America". Shared by the picker and by every row that displays a stored
 * zone, so what you pick is what you see afterwards.
 */
export function formatZoneName(zone: string): string {
  const cut = zone.lastIndexOf('/')
  const city = (cut === -1 ? zone : zone.slice(cut + 1)).replace(/_/g, ' ')
  const region = cut === -1 ? '' : zone.slice(0, cut).replace(/_/g, ' ')
  return region ? `${city} · ${region}` : city
}

/** "YYYY-MM-DD" civil date in `zone` at the given instant. */
export function zonedDateString(epochMs: number, zone: string): string {
  return DateTime.fromMillis(epochMs, { zone }).toISODate()!
}

/**
 * Absolute epoch (ms) for a wall-clock time in `zone`. `time` is "HH:MM" or
 * null (treated as 00:00). Luxon resolves DST edges deterministically — exact to
 * the minute everywhere except the rare transition hour, which is fine for day
 * boundaries and "is it past now" checks.
 */
export function wallClockToEpoch(
  date: string,
  time: string | null,
  zone: string
): number {
  const [year, month, day] = date.split('-').map(Number) as [
    number,
    number,
    number,
  ]
  const [hour, minute] = (time ? time.split(':').map(Number) : [0, 0]) as [
    number,
    number,
  ]
  return DateTime.fromObject(
    { year, month, day, hour, minute },
    { zone }
  ).toMillis()
}

/** "HH:MM" (24h) wall-clock of an instant in `zone`. */
export function formatTimeInZone(epochMs: number, zone: string): string {
  return DateTime.fromMillis(epochMs, { zone }).toFormat('HH:mm')
}

/** Short zone name for an instant, e.g. "CEST" or "GMT+9". */
export function formatZoneAbbrev(epochMs: number, zone: string): string {
  return DateTime.fromMillis(epochMs, { zone }).toFormat('ZZZZ')
}
