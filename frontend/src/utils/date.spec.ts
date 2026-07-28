import { describe, it, expect, vi, afterEach } from 'vitest'
import {
  addDays,
  daysBetween,
  msUntilNextLocalMidnight,
  isPastIso,
  isFutureIso,
  addHours,
  datetimeLocalToIso,
  formatWeekdayDay,
  formatClockTime,
  monthGridDays,
  nextMondayAfter,
  formatDateDisplay,
  formatDateShort,
  formatDateRange,
  formatBirthday,
  formatDateTime,
  formatRelativeDate,
  formatDeadline,
  formatUpcomingBirthday,
  daysUntilBirthday,
  getBirthdayCountdown,
  getMonthName,
  nowIso,
} from './date'

describe('addDays', () => {
  it('advances a calendar date, crossing month and year boundaries', () => {
    expect(addDays('2026-06-15', 1)).toBe('2026-06-16')
    expect(addDays('2026-06-30', 1)).toBe('2026-07-01')
    expect(addDays('2026-12-31', 1)).toBe('2027-01-01')
  })

  it('subtracts with a negative delta', () => {
    expect(addDays('2026-01-01', -1)).toBe('2025-12-31')
  })
})

describe('formatDateDisplay', () => {
  it('returns a non-empty string containing the year', () => {
    const result = formatDateDisplay('2024-06-15')
    expect(result).toBeTruthy()
    expect(result).toContain('2024')
  })

  it('returns different output for different dates', () => {
    expect(formatDateDisplay('2024-01-01')).not.toBe(
      formatDateDisplay('2024-12-31')
    )
  })
})

describe('formatDateShort', () => {
  it('returns a non-empty string containing the year', () => {
    const result = formatDateShort('2024-03-10')
    expect(result).toBeTruthy()
    expect(result).toContain('2024')
  })
})

describe('formatDateRange', () => {
  it('returns a string containing an en-dash for different dates', () => {
    const result = formatDateRange('2024-01-01', '2024-01-05')
    expect(result).toContain('\u2013')
  })

  it('handles same-month ranges', () => {
    const result = formatDateRange('2024-06-01', '2024-06-15')
    expect(result).toContain('2024')
  })

  it('handles cross-month ranges within same year', () => {
    const result = formatDateRange('2024-01-15', '2024-03-20')
    expect(result).toContain('2024')
  })

  it('handles cross-year ranges', () => {
    const result = formatDateRange('2023-12-25', '2024-01-05')
    expect(result).toContain('2023')
    expect(result).toContain('2024')
  })
})

describe('formatBirthday', () => {
  it('spells out the month so day/month order cannot be misread', () => {
    expect(formatBirthday('1990-05-27', 'en-US')).toBe('May 27, 1990')
    expect(formatBirthday('1990-05-27', 'nl')).toBe('27 mei 1990')
  })
})

describe('formatDateTime', () => {
  it('returns a non-empty string for an ISO timestamp', () => {
    const result = formatDateTime('2024-06-15T14:30:00Z')
    expect(result).toBeTruthy()
  })
})

describe('formatRelativeDate', () => {
  afterEach(() => {
    vi.useRealTimers()
  })

  it('returns "just now" for very recent timestamps', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2024-06-15T12:00:00Z'))
    expect(formatRelativeDate('2024-06-15T12:00:00Z')).toBe('just now')
  })

  it('returns minutes ago for timestamps within an hour', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2024-06-15T12:30:00Z'))
    expect(formatRelativeDate('2024-06-15T12:00:00Z')).toBe('30m ago')
  })

  it('returns hours ago for timestamps within a day', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2024-06-15T15:00:00Z'))
    expect(formatRelativeDate('2024-06-15T12:00:00Z')).toBe('3h ago')
  })

  it('returns days ago for timestamps within a week', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2024-06-20T12:00:00Z'))
    expect(formatRelativeDate('2024-06-15T12:00:00Z')).toBe('5d ago')
  })

  it('returns weeks ago for timestamps within four weeks', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2024-07-06T12:00:00Z'))
    expect(formatRelativeDate('2024-06-15T12:00:00Z')).toBe('3w ago')
  })

  it('uses "in" for future timestamps', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2024-06-15T12:00:00Z'))
    expect(formatRelativeDate('2024-06-15T14:30:00Z')).toBe('in 2h')
    expect(formatRelativeDate('2024-06-17T12:00:00Z')).toBe('in 2d')
  })

  it('falls back to a date string for timestamps older than four weeks', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2024-08-15T12:00:00Z'))
    const result = formatRelativeDate('2024-06-15T12:00:00Z')
    expect(result).toContain('2024')
  })
})

describe('formatDeadline', () => {
  afterEach(() => {
    vi.useRealTimers()
  })

  it('returns "Past deadline" for past dates', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2024-06-15T12:00:00Z'))
    expect(formatDeadline('2024-06-14T00:00:00Z')).toBe('Past deadline')
  })

  it('returns "Due today" for a deadline that just passed', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2024-06-15T14:00:00Z'))
    // Deadline was 2 hours ago — within same day, diffDays = ceil(-2h/24h) = 0
    expect(formatDeadline('2024-06-15T12:00:00Z')).toBe('Due today')
  })

  it('returns "Due tomorrow" for tomorrow', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2024-06-15T12:00:00Z'))
    expect(formatDeadline('2024-06-16T12:00:00Z')).toBe('Due tomorrow')
  })

  it('returns "Due in N days" for nearby dates', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2024-06-15T12:00:00Z'))
    const result = formatDeadline('2024-06-20T12:00:00Z')
    expect(result).toMatch(/^Due in \d+ days$/)
  })

  it('falls back to a date string for far-future dates', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2024-06-15T12:00:00Z'))
    const result = formatDeadline('2024-12-25T12:00:00Z')
    expect(result).toContain('2024')
  })
})

describe('getMonthName', () => {
  it('returns a non-empty string for each month', () => {
    for (let i = 0; i < 12; i++) {
      expect(getMonthName(i)).toBeTruthy()
    }
  })

  it('returns different names for different months', () => {
    const names = new Set(Array.from({ length: 12 }, (_, i) => getMonthName(i)))
    expect(names.size).toBe(12)
  })
})

describe('formatUpcomingBirthday', () => {
  afterEach(() => {
    vi.useRealTimers()
  })

  it('returns "Today" when the birthday is today', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-07-14T09:00:00'))
    expect(formatUpcomingBirthday('1990-07-14')).toBe('Today')
  })

  it('returns "Tomorrow" when the birthday is tomorrow', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-07-14T09:00:00'))
    expect(formatUpcomingBirthday('1990-07-15')).toBe('Tomorrow')
  })

  // A birthday exactly 7 days out always falls on today's weekday, so a
  // bare weekday name ("Tuesday", when today is also Tuesday) reads as
  // today. Prefix it to disambiguate. Pin "now" late in the day to keep
  // covering the original off-by-one, where time-of-day leaked into the
  // date arithmetic.
  it('labels a birthday exactly 7 days out as "Next <weekday>"', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-07-14T23:45:00'))
    expect(formatUpcomingBirthday('1990-07-21')).toBe('Next Tuesday')
  })

  it('returns a weekday name for birthdays 2-6 days out', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-07-14T09:00:00'))
    // 2026-07-16 is a Thursday
    expect(formatUpcomingBirthday('1985-07-16')).toBe('Thursday')
    // 2026-07-20 is a Monday — the far edge of the bare-weekday window
    expect(formatUpcomingBirthday('1985-07-20')).toBe('Monday')
  })

  it('falls back to a formatted date for birthdays more than 7 days out', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-07-14T09:00:00'))
    const result = formatUpcomingBirthday('1990-08-01')
    expect(result).toBe(formatBirthday('1990-08-01'))
  })

  it('rolls over to next year when the birthday already passed this year', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-07-14T09:00:00'))
    // Jan 1 has already passed for this year, so it resolves ~5.5 months out
    const result = formatUpcomingBirthday('1990-01-01')
    expect(result).toBe(formatBirthday('1990-01-01'))
  })
})

describe('nowIso', () => {
  afterEach(() => {
    vi.useRealTimers()
  })

  it('returns the current instant as a UTC ISO string, matching Date', () => {
    vi.useFakeTimers()
    const instant = new Date('2026-07-15T10:10:34.123Z')
    vi.setSystemTime(instant)
    expect(nowIso()).toBe('2026-07-15T10:10:34.123Z')
    expect(nowIso()).toBe(instant.toISOString())
  })
})

describe('daysUntilBirthday', () => {
  const now = new Date('2026-07-14T21:30:45').getTime()

  it('returns 0 for a birthday today and 1 for tomorrow', () => {
    expect(daysUntilBirthday('1990-07-14', now)).toBe(0)
    expect(daysUntilBirthday('1990-07-15', now)).toBe(1)
  })

  it('rolls over to next year when this year’s birthday has passed', () => {
    expect(daysUntilBirthday('1990-01-01', now)).toBeGreaterThan(100)
  })

  it('returns null for a missing or unparseable birthday', () => {
    expect(daysUntilBirthday(null, now)).toBeNull()
    expect(daysUntilBirthday('not-a-date', now)).toBeNull()
  })
})

describe('getBirthdayCountdown', () => {
  // 2026-07-14T21:30:45 local → 2h 29m 15s until 2026-07-15 midnight.
  const now = new Date('2026-07-14T21:30:45').getTime()

  it('formats the time to midnight, dropping the days segment under a day', () => {
    // Largest shown unit (hours) is unpadded; minutes/seconds zero-pad.
    expect(getBirthdayCountdown('1990-07-15', now)?.text).toBe('2h 29m 15s')
  })

  it('includes a days segment for birthdays further out', () => {
    // 2026-07-20 midnight is 5 days + 2h 29m 15s away. Days lead unpadded;
    // the now-interior hours zero-pad.
    expect(getBirthdayCountdown('1985-07-20', now)?.text).toBe('5d 02h 29m 15s')
  })

  it('reports loading progress through the 7-day window as a percentage', () => {
    // ~2.5h into a 7-day window ≈ 99% loaded; 5 days out ≈ 27%.
    expect(getBirthdayCountdown('1990-07-15', now)?.percent).toBe(99)
    expect(getBirthdayCountdown('1985-07-20', now)?.percent).toBe(27)
  })

  it('clamps at zero instead of going negative once midnight passes', () => {
    // Birthday is "today" (already past its midnight), so the raw diff is
    // negative — it reads all-zeroes and 100% rather than a negative timer.
    const countdown = getBirthdayCountdown('1990-07-14', now)
    expect(countdown?.text).toBe('0h 00m 00s')
    expect(countdown?.percent).toBe(100)
  })

  it('returns null for an unparseable birthday', () => {
    expect(getBirthdayCountdown('not-a-date', now)).toBeNull()
  })
})

describe('daysBetween', () => {
  it('counts whole days between two dates', () => {
    expect(daysBetween('2026-07-01', '2026-07-04')).toBe(3)
    expect(daysBetween('2026-07-01', '2026-07-01')).toBe(0)
  })

  it('stays exact across a DST transition (UTC-anchored)', () => {
    // Europe springs forward on 2026-03-29; UTC anchoring keeps the count whole.
    expect(daysBetween('2026-03-28', '2026-03-30')).toBe(2)
  })
})

describe('msUntilNextLocalMidnight', () => {
  it('counts the ms remaining until the next local midnight', () => {
    const now = new Date(2026, 6, 14, 21, 30, 0) // local 2026-07-14 21:30
    const midnight = new Date(2026, 6, 15, 0, 0, 0)
    expect(msUntilNextLocalMidnight(now.getTime())).toBe(
      midnight.getTime() - now.getTime()
    )
  })
})

describe('isPastIso / isFutureIso', () => {
  const now = Date.UTC(2026, 6, 15, 12, 0)

  it('classifies instants relative to now', () => {
    expect(isPastIso('2026-07-15T11:00:00Z', now)).toBe(true)
    expect(isPastIso('2026-07-15T13:00:00Z', now)).toBe(false)
    expect(isFutureIso('2026-07-15T13:00:00Z', now)).toBe(true)
    expect(isFutureIso('2026-07-15T11:00:00Z', now)).toBe(false)
  })
})

describe('addHours', () => {
  it('adds hours and returns a UTC ISO string', () => {
    expect(addHours('2026-07-15T10:00:00Z', 24)).toBe(
      '2026-07-16T10:00:00.000Z'
    )
    expect(addHours('2026-07-15T10:00:00Z', -2)).toBe(
      '2026-07-15T08:00:00.000Z'
    )
  })
})

describe('datetimeLocalToIso', () => {
  it('converts a local datetime-local value to a UTC ISO instant', () => {
    const iso = datetimeLocalToIso('2026-07-15T12:00')
    expect(iso.endsWith('Z')).toBe(true)
    expect(new Date(iso).getTime()).toBe(new Date('2026-07-15T12:00').getTime())
  })
})

describe('formatWeekdayDay', () => {
  it('renders short weekday and day-of-month', () => {
    // 2024-03-10 is a Sunday.
    expect(formatWeekdayDay('2024-03-10', 'en-US')).toBe('Sun 10')
  })
})

describe('formatClockTime', () => {
  it('renders a clock time', () => {
    expect(formatClockTime('2026-07-15T14:05:00Z', 'en-US')).toMatch(
      /\d{1,2}:\d{2}/
    )
  })
})

describe('monthGridDays', () => {
  it('builds a Monday-first 42-cell grid padded from adjacent months', () => {
    const days = monthGridDays(2026, 0) // January 2026; Jan 1 is a Thursday
    expect(days).toHaveLength(42)
    // The grid opens on the Monday on/before Jan 1 — 2025-12-29.
    expect(days[0].dateString).toBe('2025-12-29')
    expect(days[0].isCurrentMonth).toBe(false)
    expect(days[0].dayOfMonth).toBe(29)
    // Every in-month day is flagged; January has 31.
    expect(days.filter((d) => d.isCurrentMonth)).toHaveLength(31)
    expect(
      days.some((d) => d.dateString === '2026-01-01' && d.isCurrentMonth)
    ).toBe(true)
    expect(
      days.some((d) => d.dateString === '2026-01-31' && d.isCurrentMonth)
    ).toBe(true)
  })
})

describe('nextMondayAfter', () => {
  it('returns the Monday that opens the following week', () => {
    // 2026-07-14 is a Tuesday; 2026-07-13 a Monday.
    expect(nextMondayAfter('2026-07-14')).toBe('2026-07-20')
    expect(nextMondayAfter('2026-07-13')).toBe('2026-07-20')
  })

  it('jumps a full week when the day after is itself a Monday', () => {
    // 2026-07-19 is a Sunday; the day after is Monday 07-20 → skip to 07-27.
    expect(nextMondayAfter('2026-07-19')).toBe('2026-07-27')
  })
})
