import { describe, it, expect } from 'vitest'
import { daySummaries } from './days'
import { makeRsvp } from '@/test/factories'

// Three-day event; dates resolve via the same precedence as everywhere else
// (attendance day set → legacy range → whole event).
const EVENT = { startDate: '2026-08-01', endDate: '2026-08-03' }

describe('daySummaries', () => {
  it('counts whole-event RSVPs on every day, arriving on the first and departing on the last', () => {
    const rsvps = [
      makeRsvp({ userId: 'alice' }),
      makeRsvp({ id: 'rsvp-2', userId: 'bob' }),
    ]

    const days = daySummaries(rsvps, EVENT)

    expect(days.map((d) => d.date)).toEqual([
      '2026-08-01',
      '2026-08-02',
      '2026-08-03',
    ])
    for (const day of days) {
      expect(day.userIds).toEqual(['alice', 'bob'])
      expect(day.guests).toBe(0)
      expect(day.headcount).toBe(2)
    }
    expect(days.map((d) => d.arrivals)).toEqual([['alice', 'bob'], [], []])
    expect(days.map((d) => d.departures)).toEqual([[], [], ['alice', 'bob']])
  })

  it('resolves day sets, guests, decliners, and legacy ranges per day', () => {
    const rsvps = [
      // Comes and goes: skips the middle day, +1 guest on the last day only.
      makeRsvp({
        userId: 'alice',
        attendance: ['2026-08-01', { date: '2026-08-03', plusOnes: 1 }],
      }),
      // Legacy contiguous range, no attendance day set.
      makeRsvp({
        id: 'rsvp-2',
        userId: 'bob',
        startDate: '2026-08-02',
        endDate: '2026-08-03',
      }),
      // Declined — never counted.
      makeRsvp({ id: 'rsvp-3', userId: 'carol', attending: false }),
    ]

    const days = daySummaries(rsvps, EVENT)

    expect(days.map((d) => d.userIds)).toEqual([
      ['alice'],
      ['bob'],
      ['alice', 'bob'],
    ])
    expect(days.map((d) => d.guests)).toEqual([0, 0, 1])
    expect(days.map((d) => d.headcount)).toEqual([1, 1, 3])
    // Alice leaves after day one and comes back for day three.
    expect(days.map((d) => d.arrivals)).toEqual([['alice'], ['bob'], ['alice']])
    expect(days.map((d) => d.departures)).toEqual([
      ['alice'],
      [],
      ['alice', 'bob'],
    ])
  })

  it('returns no days while the event has no dates', () => {
    expect(
      daySummaries([makeRsvp()], { startDate: null, endDate: null })
    ).toEqual([])
  })
})
