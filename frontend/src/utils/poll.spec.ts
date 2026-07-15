import { describe, it, expect } from 'vitest'
import { formatPollDeadline, defaultPollDeadline } from './poll'

describe('formatPollDeadline', () => {
  const now = Date.UTC(2026, 6, 1, 12, 0)

  it('reports days and hours for far-off deadlines', () => {
    expect(
      formatPollDeadline(
        new Date(Date.UTC(2026, 6, 6, 14, 30)).toISOString(),
        now
      )
    ).toBe('5d 2h remaining')
  })

  it('reports hours only within a day', () => {
    expect(
      formatPollDeadline(
        new Date(Date.UTC(2026, 6, 1, 15, 45)).toISOString(),
        now
      )
    ).toBe('3h remaining')
  })

  it('reports minutes only within an hour', () => {
    expect(
      formatPollDeadline(
        new Date(Date.UTC(2026, 6, 1, 12, 20)).toISOString(),
        now
      )
    ).toBe('20m remaining')
  })

  it('reports a passed deadline', () => {
    expect(
      formatPollDeadline(
        new Date(Date.UTC(2026, 6, 1, 11, 0)).toISOString(),
        now
      )
    ).toBe('Deadline passed')
  })
})

describe('defaultPollDeadline', () => {
  it('is a week out at 23:59, formatted for a datetime-local input', () => {
    const now = new Date(2026, 6, 1, 9, 0).getTime() // local 2026-07-01 09:00
    expect(defaultPollDeadline(now)).toBe('2026-07-08T23:59')
  })
})
