import { describe, it, expect } from 'vitest'
import {
  detectAttendanceDrift,
  refillableAssignments,
  shouldSuggestAutofill,
} from './chores'
import { makeChore, makeChoreAssignment, makeRsvp } from '@/test/factories'

describe('refillableAssignments', () => {
  // Four-day event in Amsterdam, viewed on day three at 16:00 local (CET, +1).
  const ZONE = 'Europe/Amsterdam'
  const TODAY = '2026-03-03'
  const NOW_MS = Date.UTC(2026, 2, 3, 15, 0) // 16:00 in Amsterdam

  const chores = [
    makeChore({ id: 'morning', time: '10:00' }),
    makeChore({ id: 'evening', time: '17:00' }),
    makeChore({ id: 'untimed', time: null }),
  ]

  it('mirrors the server fence: today onward, minus today’s already-started timed chores', () => {
    const assignments = [
      makeChoreAssignment({
        id: 'past-day',
        choreId: 'evening',
        date: '2026-03-02',
      }),
      makeChoreAssignment({
        id: 'done-today',
        choreId: 'morning',
        date: TODAY,
      }),
      makeChoreAssignment({
        id: 'ahead-today',
        choreId: 'evening',
        date: TODAY,
      }),
      makeChoreAssignment({
        id: 'untimed-today',
        choreId: 'untimed',
        date: TODAY,
      }),
      makeChoreAssignment({
        id: 'tomorrow',
        choreId: 'morning',
        date: '2026-03-04',
      }),
    ]

    const refillable = refillableAssignments(
      assignments,
      chores,
      TODAY,
      ZONE,
      NOW_MS
    )
    expect(refillable.map((a) => a.id)).toEqual([
      'ahead-today',
      'untimed-today',
      'tomorrow',
    ])
  })
})

describe('shouldSuggestAutofill', () => {
  it('suggests while the roster is less than half full', () => {
    // 2 chores x 3 days x 1 person = 6 seats; 2 assigned is under half
    const chores = [makeChore(), makeChore({ id: 'chore-2' })]
    expect(shouldSuggestAutofill(chores, 3, 2)).toBe(true)
  })

  it('stops suggesting once the roster reaches half full', () => {
    const chores = [makeChore(), makeChore({ id: 'chore-2' })]
    expect(shouldSuggestAutofill(chores, 3, 3)).toBe(false)
  })

  it('counts multi-person chores by their seats', () => {
    // 1 chore x 2 days x 3 people = 6 seats; 2 assigned is under half
    const chores = [makeChore({ peoplePerDay: 3 })]
    expect(shouldSuggestAutofill(chores, 2, 2)).toBe(true)
  })

  it('never suggests for an empty roster', () => {
    expect(shouldSuggestAutofill([], 3, 0)).toBe(false)
  })
})

describe('detectAttendanceDrift', () => {
  // Four-day event, viewed on day three.
  const event = { startDate: '2026-03-01', endDate: '2026-03-04' }
  const TODAY = '2026-03-03'

  it('flags upcoming assignments held by someone not attending that day, ignoring past days', () => {
    // user-1 left after the first day, yet still holds slots on days 2 and 3.
    const rsvps = [makeRsvp({ userId: 'user-1', attendance: ['2026-03-01'] })]
    const assignments = [
      makeChoreAssignment({
        id: 'a-past',
        userId: 'user-1',
        date: '2026-03-02',
      }),
      makeChoreAssignment({
        id: 'a-future',
        userId: 'user-1',
        date: '2026-03-03',
      }),
    ]

    const drift = detectAttendanceDrift(assignments, rsvps, event, TODAY)
    expect(drift.staleAssignmentIds).toEqual(new Set(['a-future']))
    expect(drift.idleUserIds).toEqual([])
  })

  it('flags upcoming assignments held by someone with no attending RSVP at all', () => {
    const assignments = [
      makeChoreAssignment({
        id: 'a1',
        userId: 'user-gone',
        date: '2026-03-04',
      }),
    ]

    const drift = detectAttendanceDrift(assignments, [], event, TODAY)
    expect(drift.staleAssignmentIds).toEqual(new Set(['a1']))
  })

  it('reports attendees with remaining days but no upcoming chores while others carry slots', () => {
    const rsvps = [
      makeRsvp({ id: 'r1', userId: 'user-1' }),
      // user-2 joined for the tail end of the event and has nothing to do.
      makeRsvp({
        id: 'r2',
        userId: 'user-2',
        attendance: ['2026-03-03', '2026-03-04'],
      }),
    ]
    const assignments = [
      makeChoreAssignment({ id: 'a1', userId: 'user-1', date: '2026-03-03' }),
    ]

    const drift = detectAttendanceDrift(assignments, rsvps, event, TODAY)
    expect(drift.staleAssignmentIds).toEqual(new Set())
    expect(drift.idleUserIds).toEqual(['user-2'])
  })

  it('reports nothing for an empty or fully past roster — that is the auto-fill nudge’s job', () => {
    const rsvps = [
      makeRsvp({ id: 'r1', userId: 'user-1' }),
      makeRsvp({ id: 'r2', userId: 'user-2' }),
    ]
    // Only past assignments: nobody is "idle", nothing is stale.
    const assignments = [
      makeChoreAssignment({ id: 'a1', userId: 'user-1', date: '2026-03-01' }),
    ]

    const drift = detectAttendanceDrift(assignments, rsvps, event, TODAY)
    expect(drift.staleAssignmentIds).toEqual(new Set())
    expect(drift.idleUserIds).toEqual([])
  })
})
