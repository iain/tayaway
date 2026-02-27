import { describe, it, expect, vi, afterEach } from 'vitest'
import {
  formatDateDisplay,
  formatDateShort,
  formatDateRange,
  formatBirthday,
  formatDateTime,
  formatRelativeDate,
  formatDeadline,
  getMonthName,
} from './date'

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

  it('returns "Just now" for very recent timestamps', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2024-06-15T12:00:00Z'))
    expect(formatRelativeDate('2024-06-15T12:00:00Z')).toBe('Just now')
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

  it('returns days ago for timestamps within 30 days', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2024-06-20T12:00:00Z'))
    expect(formatRelativeDate('2024-06-15T12:00:00Z')).toBe('5d ago')
  })

  it('falls back to a date string for timestamps older than 30 days', () => {
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
