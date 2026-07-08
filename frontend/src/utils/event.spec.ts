import { describe, it, expect } from 'vitest'
import {
  countNights,
  enumerateDates,
  attendedDates,
  attendedDays,
  eventHasDates,
  eventIsPlanning,
  eventIsCurrent,
  eventIsUpcoming,
  eventIsPast,
} from './event'

describe('countNights', () => {
  it('counts nights between two consecutive dates as 1', () => {
    expect(countNights('2026-07-01', '2026-07-02')).toBe(1)
  })

  it('counts nights for a multi-day range', () => {
    expect(countNights('2026-07-01', '2026-07-04')).toBe(3)
  })

  it('counts nights across month boundary', () => {
    expect(countNights('2026-06-29', '2026-07-03')).toBe(4)
  })

  it('returns 0 for same start and end date', () => {
    expect(countNights('2026-07-01', '2026-07-01')).toBe(0)
  })

  it('counts nights for a full week', () => {
    expect(countNights('2026-06-01', '2026-06-07')).toBe(6)
  })
})

describe('enumerateDates', () => {
  it('lists an inclusive range', () => {
    expect(enumerateDates('2026-07-01', '2026-07-04')).toEqual([
      '2026-07-01',
      '2026-07-02',
      '2026-07-03',
      '2026-07-04',
    ])
  })

  it('returns a single day for equal start and end', () => {
    expect(enumerateDates('2026-07-01', '2026-07-01')).toEqual(['2026-07-01'])
  })

  it('crosses a month boundary', () => {
    expect(enumerateDates('2026-06-29', '2026-07-02')).toEqual([
      '2026-06-29',
      '2026-06-30',
      '2026-07-01',
      '2026-07-02',
    ])
  })

  it('steps in whole days across a DST transition (UTC-anchored)', () => {
    // Europe springs forward on 2026-03-29; UTC anchoring keeps the count exact.
    expect(enumerateDates('2026-03-28', '2026-03-30')).toEqual([
      '2026-03-28',
      '2026-03-29',
      '2026-03-30',
    ])
  })
})

describe('attendedDates', () => {
  const eventStart = '2026-07-01'
  const eventEnd = '2026-07-04'

  it('expands a whole-event RSVP to every event day', () => {
    expect(
      attendedDates(
        { attendance: null, startDate: null, endDate: null },
        eventStart,
        eventEnd
      )
    ).toEqual(['2026-07-01', '2026-07-02', '2026-07-03', '2026-07-04'])
  })

  it('returns the explicit come-and-go day set when present', () => {
    expect(
      attendedDates(
        {
          attendance: ['2026-07-01', '2026-07-03'],
          startDate: '2026-07-01',
          endDate: '2026-07-03',
        },
        eventStart,
        eventEnd
      )
    ).toEqual(['2026-07-01', '2026-07-03'])
  })

  it('enumerates a legacy contiguous range when there is no day set', () => {
    expect(
      attendedDates(
        { attendance: null, startDate: '2026-07-02', endDate: '2026-07-03' },
        eventStart,
        eventEnd
      )
    ).toEqual(['2026-07-02', '2026-07-03'])
  })

  it('treats an empty attendance array as the whole event', () => {
    expect(
      attendedDates(
        { attendance: [], startDate: null, endDate: null },
        eventStart,
        eventEnd
      )
    ).toEqual(['2026-07-01', '2026-07-02', '2026-07-03', '2026-07-04'])
  })
})

describe('attendedDays', () => {
  const eventStart = '2026-07-01'
  const eventEnd = '2026-07-04'

  it('carries per-day plus-ones and defaults legacy string entries to zero', () => {
    expect(
      attendedDays(
        {
          attendance: ['2026-07-01', { date: '2026-07-03', plusOnes: 2 }],
          startDate: '2026-07-01',
          endDate: '2026-07-03',
        },
        eventStart,
        eventEnd
      )
    ).toEqual([
      { date: '2026-07-01', plusOnes: 0 },
      { date: '2026-07-03', plusOnes: 2 },
    ])
  })

  it('expands a whole-event RSVP to guest-free days', () => {
    expect(
      attendedDays(
        { attendance: null, startDate: null, endDate: null },
        eventStart,
        eventEnd
      )
    ).toEqual([
      { date: '2026-07-01', plusOnes: 0 },
      { date: '2026-07-02', plusOnes: 0 },
      { date: '2026-07-03', plusOnes: 0 },
      { date: '2026-07-04', plusOnes: 0 },
    ])
  })
})

describe('eventHasDates', () => {
  it('returns true when both dates are set', () => {
    expect(
      eventHasDates({ startDate: '2026-07-01', endDate: '2026-07-04' })
    ).toBe(true)
  })

  it('returns false when startDate is null', () => {
    expect(eventHasDates({ startDate: null, endDate: '2026-07-04' })).toBe(
      false
    )
  })

  it('returns false when endDate is null', () => {
    expect(eventHasDates({ startDate: '2026-07-01', endDate: null })).toBe(
      false
    )
  })

  it('returns false when null', () => {
    expect(eventHasDates(null)).toBe(false)
  })
})

describe('eventIsPlanning', () => {
  it('returns true when startDate is null', () => {
    expect(eventIsPlanning({ startDate: null, endDate: null })).toBe(true)
  })

  it('returns false when startDate is set', () => {
    expect(
      eventIsPlanning({ startDate: '2026-07-01', endDate: '2026-07-04' })
    ).toBe(false)
  })
})

describe('eventIsCurrent', () => {
  const today = '2026-07-15'

  it('returns true when today is between startDate and endDate', () => {
    expect(
      eventIsCurrent({ startDate: '2026-07-10', endDate: '2026-07-20' }, today)
    ).toBe(true)
  })

  it('returns true when today equals startDate', () => {
    expect(
      eventIsCurrent({ startDate: '2026-07-15', endDate: '2026-07-20' }, today)
    ).toBe(true)
  })

  it('returns true when today equals endDate', () => {
    expect(
      eventIsCurrent({ startDate: '2026-07-10', endDate: '2026-07-15' }, today)
    ).toBe(true)
  })

  it('returns true for a single-day event on today', () => {
    expect(
      eventIsCurrent({ startDate: '2026-07-15', endDate: '2026-07-15' }, today)
    ).toBe(true)
  })

  it('returns false when today is before the event', () => {
    expect(
      eventIsCurrent({ startDate: '2026-07-16', endDate: '2026-07-20' }, today)
    ).toBe(false)
  })

  it('returns false when today is after the event', () => {
    expect(
      eventIsCurrent({ startDate: '2026-07-10', endDate: '2026-07-14' }, today)
    ).toBe(false)
  })

  it('returns false when startDate is null', () => {
    expect(
      eventIsCurrent({ startDate: null, endDate: '2026-07-20' }, today)
    ).toBe(false)
  })

  it('returns false when endDate is null', () => {
    expect(
      eventIsCurrent({ startDate: '2026-07-10', endDate: null }, today)
    ).toBe(false)
  })

  it('returns false when event is null', () => {
    expect(eventIsCurrent(null, today)).toBe(false)
  })
})

describe('eventIsUpcoming', () => {
  const today = '2026-07-15'

  it('returns true when startDate is in the future', () => {
    expect(
      eventIsUpcoming({ startDate: '2026-07-16', endDate: '2026-07-20' }, today)
    ).toBe(true)
  })

  it('returns false when startDate equals today (event is current)', () => {
    expect(
      eventIsUpcoming({ startDate: '2026-07-15', endDate: '2026-07-20' }, today)
    ).toBe(false)
  })

  it('returns false when startDate is in the past', () => {
    expect(
      eventIsUpcoming({ startDate: '2026-07-10', endDate: '2026-07-14' }, today)
    ).toBe(false)
  })

  it('returns false when startDate is null', () => {
    expect(eventIsUpcoming({ startDate: null, endDate: null }, today)).toBe(
      false
    )
  })
})

describe('eventIsPast', () => {
  const today = '2026-07-15'

  it('returns true when both dates are in the past', () => {
    expect(
      eventIsPast({ startDate: '2026-07-10', endDate: '2026-07-14' }, today)
    ).toBe(true)
  })

  it('returns true when startDate is past and endDate is null', () => {
    expect(eventIsPast({ startDate: '2026-07-10', endDate: null }, today)).toBe(
      true
    )
  })

  it('returns false when startDate is past but endDate is today (event is current)', () => {
    expect(
      eventIsPast({ startDate: '2026-07-10', endDate: '2026-07-15' }, today)
    ).toBe(false)
  })

  it('returns false when startDate is past but endDate is in the future (event is current)', () => {
    expect(
      eventIsPast({ startDate: '2026-07-10', endDate: '2026-07-20' }, today)
    ).toBe(false)
  })

  it('returns false when startDate is in the future', () => {
    expect(
      eventIsPast({ startDate: '2026-07-16', endDate: '2026-07-20' }, today)
    ).toBe(false)
  })

  it('returns false when startDate is null', () => {
    expect(eventIsPast({ startDate: null, endDate: null }, today)).toBe(false)
  })
})
