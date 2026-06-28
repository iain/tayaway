import { describe, it, expect } from 'vitest'
import {
  zonedDateString,
  wallClockToEpoch,
  addDays,
  deviceTimezone,
  formatTimeInZone,
  formatZoneAbbrev,
} from './timezone'

describe('zonedDateString', () => {
  // 2026-06-15T23:30:00Z — late evening in UTC, already the next day in Tokyo.
  const late = Date.UTC(2026, 5, 15, 23, 30)

  it('gives the civil date in the requested zone', () => {
    expect(zonedDateString(late, 'UTC')).toBe('2026-06-15')
    expect(zonedDateString(late, 'Asia/Tokyo')).toBe('2026-06-16') // +09:00
    expect(zonedDateString(late, 'America/New_York')).toBe('2026-06-15') // -04:00
  })
})

describe('wallClockToEpoch', () => {
  it('reads a summer wall-clock at the DST offset', () => {
    // 18:00 Amsterdam on 2026-07-01 is CEST (+02:00) = 16:00 UTC.
    expect(wallClockToEpoch('2026-07-01', '18:00', 'Europe/Amsterdam')).toBe(
      Date.UTC(2026, 6, 1, 16, 0)
    )
  })

  it('reads a winter wall-clock at the standard offset', () => {
    // 18:00 Amsterdam on 2026-01-01 is CET (+01:00) = 17:00 UTC.
    expect(wallClockToEpoch('2026-01-01', '18:00', 'Europe/Amsterdam')).toBe(
      Date.UTC(2026, 0, 1, 17, 0)
    )
  })

  it('treats a null time as the start of the day', () => {
    expect(wallClockToEpoch('2026-06-15', null, 'UTC')).toBe(
      Date.UTC(2026, 5, 15, 0, 0)
    )
  })

  it('is exact for a zone equal to UTC', () => {
    expect(wallClockToEpoch('2026-06-15', '12:00', 'UTC')).toBe(
      Date.UTC(2026, 5, 15, 12, 0)
    )
  })
})

describe('addDays', () => {
  it('advances a calendar date, crossing month and year boundaries', () => {
    expect(addDays('2026-06-15', 1)).toBe('2026-06-16')
    expect(addDays('2026-06-30', 1)).toBe('2026-07-01')
    expect(addDays('2026-12-31', 1)).toBe('2027-01-01')
  })
})

describe('formatTimeInZone', () => {
  // 16:00 UTC on 2026-07-01.
  const instant = Date.UTC(2026, 6, 1, 16, 0)

  it('renders the wall-clock time in the requested zone', () => {
    expect(formatTimeInZone(instant, 'UTC')).toBe('16:00')
    expect(formatTimeInZone(instant, 'Europe/Amsterdam')).toBe('18:00') // +02:00
    expect(formatTimeInZone(instant, 'America/New_York')).toBe('12:00') // -04:00
  })
})

describe('formatZoneAbbrev', () => {
  it('gives a non-empty short zone name that shifts with DST', () => {
    // Real browsers render "CEST"/"CET"; a limited-ICU runtime renders
    // "GMT+2"/"GMT+1". Either way it's non-empty and differs across the
    // transition — that's what the tooltip relies on.
    const summer = formatZoneAbbrev(
      Date.UTC(2026, 6, 1, 16, 0),
      'Europe/Amsterdam'
    )
    const winter = formatZoneAbbrev(
      Date.UTC(2026, 0, 1, 16, 0),
      'Europe/Amsterdam'
    )
    expect(summer).toBeTruthy()
    expect(winter).toBeTruthy()
    expect(summer).not.toBe(winter)
  })
})

describe('deviceTimezone', () => {
  it('returns the Intl-resolved device zone', () => {
    expect(deviceTimezone()).toBe(
      Intl.DateTimeFormat().resolvedOptions().timeZone
    )
  })
})
