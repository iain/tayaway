import { describe, it, expect, vi, afterEach } from 'vitest'
import {
  addDays,
  formatDateDisplay,
  formatDateShort,
  formatDateRange,
  formatBirthday,
  formatDateTime,
  formatRelativeDate,
  formatDeadline,
  formatUpcomingBirthday,
  getMonthName,
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
  it('returns a non-empty string containing the year', () => {
    const result = formatBirthday('1990-05-27')
    expect(result).toBeTruthy()
    expect(result).toContain('1990')
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
