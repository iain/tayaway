import { Scope } from '@/api/scope'
import { describe, it, expect, beforeEach } from 'vitest'
import { ref, type Ref } from 'vue'
import { createPinia, setActivePinia } from 'pinia'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useAuthStore } from '@/stores/auth'
import {
  makeEvent,
  makeChoreRoster,
  makeChore,
  makeChoreAssignment,
} from '@/test/factories'
import type { PoolObject } from '@/types/pool'
import { useUpcomingChores, MAX_VISIBLE_CHORES } from './useUpcomingChores'

const TODAY = '2026-06-15'
const TOMORROW = '2026-06-16'
const YESTERDAY = '2026-06-14'
const DAY_AFTER_TOMORROW = '2026-06-17'

// A `now` ref pinned to a wall-clock moment on TODAY (local time). Injecting it
// makes the "done 1h after" / day-boundary rules deterministic regardless of
// the test runner's timezone.
function nowAt(hour = 12, minute = 0): Ref<number> {
  return ref(new Date(2026, 5, 15, hour, minute, 0).getTime())
}

function signIn(userId = 'user-1'): void {
  useAuthStore().user = {
    id: userId,
    email: `${userId}@example.com`,
    name: null,
    phoneNumber: null,
    birthday: null,
    locationName: null,
    latitude: null,
    longitude: null,
    iban: null,
    ibanHolderName: null,
  }
}

function seed(objects: PoolObject[]): void {
  useObjectPoolStore().importObjects(objects, {
    scope: Scope.workspace('test'),
  })
}

// One event → roster → chore → assignment chain, with the bits a test cares
// about overridable. Distinct assignmentIds get distinct chores by default.
function choreChain(opts: {
  assignmentId: string
  date: string
  userId?: string
  time?: string | null
  choreName?: string
  eventId?: string
  eventName?: string
}): PoolObject[] {
  const eventId = opts.eventId ?? 'evt-1'
  const rosterId = `roster-${eventId}`
  const choreId = `chore-${opts.assignmentId}`
  return [
    makeEvent({
      id: eventId,
      name: opts.eventName ?? 'Lake House',
      startDate: '2026-06-10',
      endDate: '2026-06-25',
    }),
    makeChoreRoster({ id: rosterId, eventId }),
    makeChore({
      id: choreId,
      choreRosterId: rosterId,
      name: opts.choreName ?? 'Dishes',
      time: opts.time ?? null,
    }),
    makeChoreAssignment({
      id: opts.assignmentId,
      choreId,
      userId: opts.userId ?? 'user-1',
      date: opts.date,
    }),
  ]
}

describe('useUpcomingChores', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    signIn()
  })

  it('lists a chore assigned to me today', () => {
    seed(
      choreChain({
        assignmentId: 'a1',
        date: TODAY,
        choreName: 'Cooking',
        eventName: 'Mountain Cabin',
      })
    )

    const { upcomingChores } = useUpcomingChores(nowAt())

    expect(upcomingChores.value).toHaveLength(1)
    expect(upcomingChores.value[0]).toMatchObject({
      assignmentId: 'a1',
      choreName: 'Cooking',
      eventId: 'evt-1',
      eventName: 'Mountain Cabin',
      date: TODAY,
      time: null,
      day: 'today',
    })
  })

  it('excludes chores assigned to other people', () => {
    seed(choreChain({ assignmentId: 'a1', date: TODAY, userId: 'user-2' }))

    const { upcomingChores } = useUpcomingChores(nowAt())

    expect(upcomingChores.value).toHaveLength(0)
  })

  it("includes tomorrow's chores, labelled as such", () => {
    seed(choreChain({ assignmentId: 'a1', date: TOMORROW }))

    const { upcomingChores } = useUpcomingChores(nowAt())

    expect(upcomingChores.value).toHaveLength(1)
    expect(upcomingChores.value[0]!.day).toBe('tomorrow')
  })

  it('excludes chores beyond tomorrow', () => {
    seed(choreChain({ assignmentId: 'a1', date: DAY_AFTER_TOMORROW }))

    const { upcomingChores } = useUpcomingChores(nowAt())

    expect(upcomingChores.value).toHaveLength(0)
  })

  it('excludes past days', () => {
    seed(choreChain({ assignmentId: 'a1', date: YESTERDAY }))

    const { upcomingChores } = useUpcomingChores(nowAt())

    expect(upcomingChores.value).toHaveLength(0)
  })

  it('keeps a timed chore until one hour after its time', () => {
    seed(choreChain({ assignmentId: 'a1', date: TODAY, time: '12:00' }))

    // 12:30 — within the hour after 12:00, still due.
    const { upcomingChores } = useUpcomingChores(nowAt(12, 30))

    expect(upcomingChores.value).toHaveLength(1)
  })

  it('drops a timed chore once an hour has passed', () => {
    seed(choreChain({ assignmentId: 'a1', date: TODAY, time: '12:00' }))

    // 13:01 — past 12:00 + 1h, considered done.
    const { upcomingChores } = useUpcomingChores(nowAt(13, 1))

    expect(upcomingChores.value).toHaveLength(0)
  })

  it('keeps an untimed chore for the whole of today', () => {
    seed(choreChain({ assignmentId: 'a1', date: TODAY, time: null }))

    // Late evening — an untimed chore is only "done" at end of day.
    const { upcomingChores } = useUpcomingChores(nowAt(23, 30))

    expect(upcomingChores.value).toHaveLength(1)
  })

  it('orders today before tomorrow, and all-day before timed within a day', () => {
    seed([
      ...choreChain({
        assignmentId: 'today-evening',
        date: TODAY,
        time: '18:00',
      }),
      ...choreChain({ assignmentId: 'today-allday', date: TODAY, time: null }),
      ...choreChain({
        assignmentId: 'today-morning',
        date: TODAY,
        time: '09:00',
      }),
      ...choreChain({
        assignmentId: 'tomorrow-allday',
        date: TOMORROW,
        time: null,
      }),
    ])

    // 06:00 so none of today's timed chores have lapsed yet.
    const { upcomingChores } = useUpcomingChores(nowAt(6, 0))

    expect(upcomingChores.value.map((c) => c.assignmentId)).toEqual([
      'today-allday',
      'today-morning',
      'today-evening',
      'tomorrow-allday',
    ])
  })

  it('caps the visible list and lets today crowd out tomorrow', () => {
    seed([
      ...choreChain({ assignmentId: 't1', date: TODAY, time: '06:00' }),
      ...choreChain({ assignmentId: 't2', date: TODAY, time: '07:00' }),
      ...choreChain({ assignmentId: 't3', date: TODAY, time: '08:00' }),
      ...choreChain({ assignmentId: 't4', date: TODAY, time: '09:00' }),
      ...choreChain({ assignmentId: 't5', date: TODAY, time: '10:00' }),
      ...choreChain({ assignmentId: 'tomorrow', date: TOMORROW, time: null }),
    ])

    const { upcomingChores, visibleChores, hiddenCount } = useUpcomingChores(
      nowAt(5, 0)
    )

    expect(upcomingChores.value).toHaveLength(6)
    expect(visibleChores.value).toHaveLength(MAX_VISIBLE_CHORES)
    // Today fills every visible slot; tomorrow's chore is pushed into the overflow.
    expect(visibleChores.value.every((c) => c.day === 'today')).toBe(true)
    expect(hiddenCount.value).toBe(6 - MAX_VISIBLE_CHORES)
  })

  it('aggregates chores across multiple current events', () => {
    seed([
      ...choreChain({
        assignmentId: 'a1',
        date: TODAY,
        eventId: 'evt-1',
        eventName: 'Lake House',
      }),
      ...choreChain({
        assignmentId: 'a2',
        date: TODAY,
        eventId: 'evt-2',
        eventName: 'Ski Trip',
      }),
    ])

    const { upcomingChores } = useUpcomingChores(nowAt())

    expect(upcomingChores.value.map((c) => c.eventName).sort()).toEqual([
      'Lake House',
      'Ski Trip',
    ])
  })

  it('returns nothing when no one is signed in', () => {
    useAuthStore().user = null
    seed(choreChain({ assignmentId: 'a1', date: TODAY }))

    const { upcomingChores } = useUpcomingChores(nowAt())

    expect(upcomingChores.value).toHaveLength(0)
  })

  it('reacts to the clock: a timed chore drops off as its hour passes', () => {
    seed(choreChain({ assignmentId: 'a1', date: TODAY, time: '12:00' }))

    const now = nowAt(12, 30)
    const { upcomingChores } = useUpcomingChores(now)
    expect(upcomingChores.value).toHaveLength(1)

    // Advance past 12:00 + 1h.
    now.value = new Date(2026, 5, 15, 13, 30, 0).getTime()
    expect(upcomingChores.value).toHaveLength(0)
  })
})
