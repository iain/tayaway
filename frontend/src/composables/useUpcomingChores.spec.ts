import { Scope } from '@/api/scope'
import { describe, it, expect, beforeEach } from 'vitest'
import { ref, type Ref } from 'vue'
import { createPinia, setActivePinia } from 'pinia'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useAuthStore } from '@/stores/auth'
import {
  makeAttendance,
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

// A `now` ref pinned to a UTC instant on TODAY. The default event zone in these
// tests is "UTC", so the wall-clock equals UTC and the windows read cleanly;
// one test below uses a real zone to prove the event-zone reckoning.
function nowUtc(hour = 12, minute = 0): Ref<number> {
  return ref(Date.UTC(2026, 5, 15, hour, minute, 0))
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
    timezone: null,
  }
}

function seed(objects: PoolObject[]): void {
  useObjectPoolStore().importObjects(objects, {
    scope: Scope.workspace('test'),
  })
}

// One event -> roster -> chore -> assignment chain, with the bits a test cares
// about overridable. Distinct assignmentIds get distinct chores by default.
function choreChain(opts: {
  assignmentId: string
  date: string
  userId?: string
  time?: string | null
  choreName?: string
  eventId?: string
  eventName?: string
  zone?: string
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
      timezone: opts.zone ?? 'UTC',
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

    const { upcomingChores } = useUpcomingChores(nowUtc())

    expect(upcomingChores.value).toHaveLength(1)
    expect(upcomingChores.value[0]).toMatchObject({
      assignmentId: 'a1',
      choreName: 'Cooking',
      eventId: 'evt-1',
      eventName: 'Mountain Cabin',
      date: TODAY,
      time: null,
      timezone: 'UTC',
      day: 'today',
    })
  })

  it('excludes chores assigned to other people', () => {
    seed(choreChain({ assignmentId: 'a1', date: TODAY, userId: 'user-2' }))

    const { upcomingChores } = useUpcomingChores(nowUtc())

    expect(upcomingChores.value).toHaveLength(0)
  })

  it('matches my chores through the attendance behind the assignment', () => {
    // The assignment carries no userId (a guest-era row shape); it is mine
    // because its attendance is my member row on the event.
    const [event, roster, chore] = choreChain({
      assignmentId: 'a1',
      date: TODAY,
    })
    seed([
      event!,
      roster!,
      chore!,
      makeAttendance({ id: 'att-mine', eventId: 'evt-1', userId: 'user-1' }),
      makeChoreAssignment({
        id: 'a1',
        choreId: 'chore-a1',
        attendanceId: 'att-mine',
        userId: null,
        date: TODAY,
      }),
    ])

    const { upcomingChores } = useUpcomingChores(nowUtc())

    expect(upcomingChores.value).toHaveLength(1)
  })

  it("excludes another member's chore even when the mirrored userId is stale", () => {
    const [event, roster, chore] = choreChain({
      assignmentId: 'a1',
      date: TODAY,
    })
    seed([
      event!,
      roster!,
      chore!,
      makeAttendance({ id: 'att-mine', eventId: 'evt-1', userId: 'user-1' }),
      makeAttendance({ id: 'att-other', eventId: 'evt-1', userId: 'user-2' }),
      // Mirrored userId says me, but the attendance link says user-2: the
      // link wins, the row is theirs.
      makeChoreAssignment({
        id: 'a1',
        choreId: 'chore-a1',
        attendanceId: 'att-other',
        userId: 'user-1',
        date: TODAY,
      }),
    ])

    const { upcomingChores } = useUpcomingChores(nowUtc())

    expect(upcomingChores.value).toHaveLength(0)
  })

  it("includes tomorrow's chores, labelled as such", () => {
    seed(choreChain({ assignmentId: 'a1', date: TOMORROW }))

    const { upcomingChores } = useUpcomingChores(nowUtc())

    expect(upcomingChores.value).toHaveLength(1)
    expect(upcomingChores.value[0]!.day).toBe('tomorrow')
  })

  it('excludes chores beyond tomorrow', () => {
    seed(choreChain({ assignmentId: 'a1', date: DAY_AFTER_TOMORROW }))

    const { upcomingChores } = useUpcomingChores(nowUtc())

    expect(upcomingChores.value).toHaveLength(0)
  })

  it('excludes past days', () => {
    seed(choreChain({ assignmentId: 'a1', date: YESTERDAY }))

    const { upcomingChores } = useUpcomingChores(nowUtc())

    expect(upcomingChores.value).toHaveLength(0)
  })

  it('keeps a timed chore until one hour after its time', () => {
    seed(choreChain({ assignmentId: 'a1', date: TODAY, time: '12:00' }))

    // 12:30 — within the hour after 12:00, still due.
    const { upcomingChores } = useUpcomingChores(nowUtc(12, 30))

    expect(upcomingChores.value).toHaveLength(1)
  })

  it('drops a timed chore once an hour has passed', () => {
    seed(choreChain({ assignmentId: 'a1', date: TODAY, time: '12:00' }))

    // 13:01 — past 12:00 + 1h, considered done.
    const { upcomingChores } = useUpcomingChores(nowUtc(13, 1))

    expect(upcomingChores.value).toHaveLength(0)
  })

  it('keeps an untimed chore for the whole of today', () => {
    seed(choreChain({ assignmentId: 'a1', date: TODAY, time: null }))

    // Late evening — an untimed chore is only "done" at end of day.
    const { upcomingChores } = useUpcomingChores(nowUtc(23, 30))

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
    const { upcomingChores } = useUpcomingChores(nowUtc(6, 0))

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
      nowUtc(5, 0)
    )

    expect(upcomingChores.value).toHaveLength(6)
    expect(visibleChores.value).toHaveLength(MAX_VISIBLE_CHORES)
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

    const { upcomingChores } = useUpcomingChores(nowUtc())

    expect(upcomingChores.value.map((c) => c.eventName).sort()).toEqual([
      'Lake House',
      'Ski Trip',
    ])
  })

  it("buckets a chore by the event's zone, not the device's", () => {
    // 20:00 UTC is already 2026-06-16 in Tokyo (+09:00) but still 2026-06-15 in
    // UTC. A chore dated the 16th is therefore "today" for a Tokyo event and
    // "tomorrow" for a UTC event.
    seed([
      ...choreChain({
        assignmentId: 'tokyo',
        date: TOMORROW,
        eventId: 'evt-tokyo',
        zone: 'Asia/Tokyo',
      }),
      ...choreChain({
        assignmentId: 'utc',
        date: TOMORROW,
        eventId: 'evt-utc',
        zone: 'UTC',
      }),
    ])

    const { upcomingChores } = useUpcomingChores(nowUtc(20, 0))
    const byId = new Map(upcomingChores.value.map((c) => [c.assignmentId, c]))

    expect(byId.get('tokyo')!.day).toBe('today')
    expect(byId.get('utc')!.day).toBe('tomorrow')
  })

  it('returns nothing when no one is signed in', () => {
    useAuthStore().user = null
    seed(choreChain({ assignmentId: 'a1', date: TODAY }))

    const { upcomingChores } = useUpcomingChores(nowUtc())

    expect(upcomingChores.value).toHaveLength(0)
  })

  it('reacts to the clock: a timed chore drops off as its hour passes', () => {
    seed(choreChain({ assignmentId: 'a1', date: TODAY, time: '12:00' }))

    const now = nowUtc(12, 30)
    const { upcomingChores } = useUpcomingChores(now)
    expect(upcomingChores.value).toHaveLength(1)

    // Advance past 12:00 + 1h.
    now.value = Date.UTC(2026, 5, 15, 13, 30, 0)
    expect(upcomingChores.value).toHaveLength(0)
  })
})
