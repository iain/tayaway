import { describe, it, expect } from 'vitest'
import { formatPollDeadline, defaultPollDeadline, rankDateRanges } from './poll'

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

describe('rankDateRanges', () => {
  function range(
    startDate: string,
    yes: number,
    preferably_not: number,
    no: number
  ) {
    return {
      startDate,
      voteSummary: {
        yes,
        preferably_not,
        no,
        total: yes + preferably_not + no,
      },
    }
  }

  it('breaks a tie on yes votes in favour of the option with fewer no votes', () => {
    const objectedTo = range('2027-03-08', 2, 0, 5)
    const uncontested = range('2027-03-15', 2, 0, 0)

    expect(rankDateRanges([objectedTo, uncontested])).toEqual([
      uncontested,
      objectedTo,
    ])
  })

  it('breaks a remaining tie in favour of fewer preferably-not votes', () => {
    const reluctant = range('2027-03-08', 1, 2, 1)
    const willing = range('2027-03-15', 1, 0, 1)

    expect(rankDateRanges([reluctant, willing])).toEqual([willing, reluctant])
  })

  it('falls back to chronological order for identical tallies', () => {
    const later = range('2027-03-08', 1, 0, 1)
    const earlier = range('2026-12-07', 1, 0, 1)

    expect(rankDateRanges([later, earlier])).toEqual([earlier, later])
  })
})
