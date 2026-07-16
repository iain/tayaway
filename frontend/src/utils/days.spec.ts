import { describe, it, expect } from 'vitest'
import { daySummaries } from './days'
import { makeAttendance } from '@/test/factories'

// Three-day event; a going row's explicit day set wins, NULL means the
// whole event, and non-going rows are never counted.
const EVENT = { startDate: '2026-08-01', endDate: '2026-08-03' }

/** The person behind each returned attendance, for terse assertions. */
function who(list: { userId: string | null; guestId: string | null }[]) {
  return list.map((a) => a.userId ?? a.guestId)
}

describe('daySummaries', () => {
  it('counts whole-event attendances on every day, arriving on the first and departing on the last', () => {
    const attendances = [
      makeAttendance({ userId: 'alice' }),
      makeAttendance({ id: 'att-2', userId: 'bob' }),
    ]

    const days = daySummaries(attendances, EVENT)

    expect(days.map((d) => d.date)).toEqual([
      '2026-08-01',
      '2026-08-02',
      '2026-08-03',
    ])
    for (const day of days) {
      expect(who(day.present)).toEqual(['alice', 'bob'])
      expect(day.headcount).toBe(2)
    }
    expect(days.map((d) => who(d.arrivals))).toEqual([['alice', 'bob'], [], []])
    expect(days.map((d) => who(d.departures))).toEqual([
      [],
      [],
      ['alice', 'bob'],
    ])
  })

  it('resolves day sets, guest rows, decliners, and pending rows per day', () => {
    const attendances = [
      // Comes and goes: skips the middle day.
      makeAttendance({
        userId: 'alice',
        days: ['2026-08-01', '2026-08-03'],
      }),
      // Bob covers the last two days.
      makeAttendance({
        id: 'att-2',
        userId: 'bob',
        days: ['2026-08-02', '2026-08-03'],
      }),
      // A going guest on the last day only — an attendee like any other:
      // present, arriving, and departing by identity, not a counter.
      makeAttendance({
        id: 'att-3',
        userId: null,
        guestId: 'guest-1',
        hostUserId: 'alice',
        days: ['2026-08-03'],
      }),
      // Declined and pending — never counted.
      makeAttendance({ id: 'att-4', userId: 'carol', status: 'declined' }),
      makeAttendance({ id: 'att-5', userId: 'dave', status: 'pending' }),
    ]

    const days = daySummaries(attendances, EVENT)

    expect(days.map((d) => who(d.present))).toEqual([
      ['alice'],
      ['bob'],
      ['alice', 'bob', 'guest-1'],
    ])
    expect(days.map((d) => d.headcount)).toEqual([1, 1, 3])
    // Alice leaves after day one and comes back for day three; the guest
    // arrives on the last day alongside her.
    expect(days.map((d) => who(d.arrivals))).toEqual([
      ['alice'],
      ['bob'],
      ['alice', 'guest-1'],
    ])
    expect(days.map((d) => who(d.departures))).toEqual([
      ['alice'],
      [],
      ['alice', 'bob', 'guest-1'],
    ])
  })

  it('hands back the attendance objects themselves so callers can resolve attendees', () => {
    const guest = makeAttendance({
      id: 'att-g',
      userId: null,
      guestId: 'guest-1',
      hostUserId: 'alice',
    })

    const days = daySummaries([guest], EVENT)

    expect(days[0]!.present).toEqual([guest])
  })

  it('returns no days while the event has no dates', () => {
    expect(
      daySummaries([makeAttendance()], { startDate: null, endDate: null })
    ).toEqual([])
  })
})
