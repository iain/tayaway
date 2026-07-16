import { describe, it, expect } from 'vitest'
import {
  assignableAttendancesOn,
  assignmentPerson,
  refillableAssignments,
  shouldSuggestAutofill,
  staleAssignmentIds,
} from './chores'
import {
  makeAttendance,
  makeChore,
  makeChoreAssignment,
  makeGuest,
  makeHydratedAttendance,
  makeMember,
} from '@/test/factories'

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

describe('staleAssignmentIds', () => {
  // Four-day event, viewed on day three.
  const event = { startDate: '2026-03-01', endDate: '2026-03-04' }
  const TODAY = '2026-03-03'

  it('flags upcoming assignments whose attendance no longer covers that day, ignoring past days', () => {
    // att-1 left after the first day, yet still holds slots on days 2 and 3.
    const attendances = [
      makeAttendance({ id: 'att-1', userId: 'user-1', days: ['2026-03-01'] }),
    ]
    const assignments = [
      makeChoreAssignment({
        id: 'a-past',
        attendanceId: 'att-1',
        userId: 'user-1',
        date: '2026-03-02',
      }),
      makeChoreAssignment({
        id: 'a-future',
        attendanceId: 'att-1',
        userId: 'user-1',
        date: '2026-03-03',
      }),
    ]

    expect(staleAssignmentIds(assignments, attendances, event, TODAY)).toEqual(
      new Set(['a-future'])
    )
  })

  it('flags upcoming assignments held by someone with no attendance row at all', () => {
    const assignments = [
      makeChoreAssignment({
        id: 'a1',
        attendanceId: 'att-gone',
        userId: 'user-gone',
        date: '2026-03-04',
      }),
    ]

    expect(staleAssignmentIds(assignments, [], event, TODAY)).toEqual(
      new Set(['a1'])
    )
  })

  it('trusts a guest attendance covering the day', () => {
    const attendances = [
      makeAttendance({
        id: 'att-g',
        userId: null,
        guestId: 'guest-1',
        hostUserId: 'user-1',
        days: ['2026-03-04'],
      }),
    ]
    const assignments = [
      makeChoreAssignment({
        id: 'a-guest',
        attendanceId: 'att-g',
        userId: null,
        date: '2026-03-04',
      }),
    ]

    expect(staleAssignmentIds(assignments, attendances, event, TODAY)).toEqual(
      new Set()
    )
  })

  it('resolves legacy rows without an attendance link through their userId', () => {
    const attendances = [
      makeAttendance({ id: 'att-1', userId: 'user-1', days: ['2026-03-04'] }),
    ]
    const assignments = [
      makeChoreAssignment({
        id: 'a-covered',
        attendanceId: null,
        userId: 'user-1',
        date: '2026-03-04',
      }),
      makeChoreAssignment({
        id: 'a-uncovered',
        attendanceId: null,
        userId: 'user-1',
        date: '2026-03-03',
      }),
    ]

    expect(staleAssignmentIds(assignments, attendances, event, TODAY)).toEqual(
      new Set(['a-uncovered'])
    )
  })
})

describe('assignmentPerson', () => {
  const member = makeMember({ userId: 'user-1', name: 'Alice' })
  const memberMap = new Map([['user-1', member]])

  it('resolves the holder through their attendance', () => {
    const attendance = makeHydratedAttendance(
      { id: 'att-1', userId: 'user-1' },
      { member }
    )
    const person = assignmentPerson(
      makeChoreAssignment({ attendanceId: 'att-1', userId: 'user-1' }),
      new Map([['att-1', attendance]]),
      memberMap
    )

    expect(person).toEqual({ name: 'Alice', isGuest: false, userId: 'user-1' })
  })

  it('resolves a guest holder', () => {
    const guest = makeGuest({ id: 'guest-1', name: 'Emma' })
    const attendance = makeHydratedAttendance(
      {
        id: 'att-g',
        userId: null,
        guestId: 'guest-1',
        hostUserId: 'user-1',
      },
      { guest }
    )
    const person = assignmentPerson(
      makeChoreAssignment({ attendanceId: 'att-g', userId: null }),
      new Map([['att-g', attendance]]),
      memberMap
    )

    expect(person).toEqual({ name: 'Emma', isGuest: true, userId: null })
  })

  it('falls back to the mirrored userId for legacy rows', () => {
    const person = assignmentPerson(
      makeChoreAssignment({ attendanceId: null, userId: 'user-1' }),
      new Map(),
      memberMap
    )

    expect(person).toEqual({ name: 'Alice', isGuest: false, userId: 'user-1' })
  })

  it('shows ? for an unresolvable holder', () => {
    const person = assignmentPerson(
      makeChoreAssignment({ attendanceId: null, userId: 'user-gone' }),
      new Map(),
      memberMap
    )

    expect(person.name).toBe('?')
  })
})

describe('assignableAttendancesOn', () => {
  const event = { startDate: '2026-03-01', endDate: '2026-03-04' }
  const member = makeMember({ userId: 'user-1', name: 'Alice' })

  it('offers going attendees covering the date, guests included, not absentees', () => {
    const there = makeHydratedAttendance(
      { id: 'att-1', userId: 'user-1' },
      { member }
    )
    const gone = makeHydratedAttendance(
      {
        id: 'att-2',
        userId: 'user-2',
        days: ['2026-03-01'],
      },
      { member: makeMember({ id: 'm2', userId: 'user-2', name: 'Bob' }) }
    )
    const declined = makeHydratedAttendance(
      { id: 'att-3', userId: 'user-3', status: 'declined' },
      { member: makeMember({ id: 'm3', userId: 'user-3', name: 'Cleo' }) }
    )
    const guest = makeHydratedAttendance(
      {
        id: 'att-g',
        userId: null,
        guestId: 'guest-1',
        hostUserId: 'user-1',
      },
      { guest: makeGuest() }
    )

    const result = assignableAttendancesOn(
      '2026-03-03',
      [there, gone, declined, guest],
      event
    )

    expect(result.map((a) => a.id)).toEqual(['att-1', 'att-g'])
  })

  it('offers nobody when the event has no dates', () => {
    const there = makeHydratedAttendance(
      { id: 'att-1', userId: 'user-1' },
      { member }
    )
    expect(
      assignableAttendancesOn('2026-03-03', [there], {
        startDate: null,
        endDate: null,
      })
    ).toEqual([])
  })
})
