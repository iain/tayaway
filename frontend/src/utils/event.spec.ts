import { describe, it, expect } from 'vitest'
import {
  countNights,
  eventHasDates,
  eventIsPlanning,
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

describe('eventIsUpcoming', () => {
  it('returns true when startDate is in the future', () => {
    expect(
      eventIsUpcoming({ startDate: '2099-01-01', endDate: '2099-01-04' })
    ).toBe(true)
  })

  it('returns false when startDate is in the past', () => {
    expect(
      eventIsUpcoming({ startDate: '2020-01-01', endDate: '2020-01-04' })
    ).toBe(false)
  })

  it('returns false when startDate is null', () => {
    expect(eventIsUpcoming({ startDate: null, endDate: null })).toBe(false)
  })
})

describe('eventIsPast', () => {
  it('returns true when startDate is in the past', () => {
    expect(
      eventIsPast({ startDate: '2020-01-01', endDate: '2020-01-04' })
    ).toBe(true)
  })

  it('returns false when startDate is in the future', () => {
    expect(
      eventIsPast({ startDate: '2099-01-01', endDate: '2099-01-04' })
    ).toBe(false)
  })

  it('returns false when startDate is null', () => {
    expect(eventIsPast({ startDate: null, endDate: null })).toBe(false)
  })
})
