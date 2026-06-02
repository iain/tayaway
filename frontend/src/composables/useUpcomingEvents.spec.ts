import { Scope } from '@/api/scope'
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useAuthStore } from '@/stores/auth'
import { makeEvent, makeRsvp } from '@/test/factories'
import { useUpcomingEvents } from './useUpcomingEvents'

const TODAY = new Date('2026-06-02T12:00:00Z')

function signIn(userId: string): void {
  const auth = useAuthStore()
  auth.user = {
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

describe('useUpcomingEvents', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.useFakeTimers()
    vi.setSystemTime(TODAY)
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  it('returns only future events, excluding past, current, and planning', () => {
    const pool = useObjectPoolStore()
    signIn('user-1')
    pool.importObjects(
      [
        makeEvent({
          id: 'past',
          startDate: '2026-05-01',
          endDate: '2026-05-02',
        }),
        makeEvent({
          id: 'current',
          startDate: '2026-06-01',
          endDate: '2026-06-03',
        }),
        makeEvent({
          id: 'upcoming',
          startDate: '2026-06-10',
          endDate: '2026-06-12',
        }),
        makeEvent({ id: 'planning', startDate: null, endDate: null }),
      ],
      { scope: Scope.workspace('test') }
    )

    const { upcomingEvents } = useUpcomingEvents()

    expect(upcomingEvents.value.map((e) => e.eventId)).toEqual(['upcoming'])
  })

  it('sorts upcoming events by start date ascending', () => {
    const pool = useObjectPoolStore()
    signIn('user-1')
    pool.importObjects(
      [
        makeEvent({
          id: 'july',
          startDate: '2026-07-01',
          endDate: '2026-07-02',
        }),
        makeEvent({
          id: 'june',
          startDate: '2026-06-10',
          endDate: '2026-06-12',
        }),
      ],
      { scope: Scope.workspace('test') }
    )

    const { upcomingEvents } = useUpcomingEvents()

    expect(upcomingEvents.value.map((e) => e.eventId)).toEqual(['june', 'july'])
  })

  it('flags needsRsvp based on whether the current user has responded', () => {
    const pool = useObjectPoolStore()
    signIn('user-1')
    pool.importObjects(
      [
        makeEvent({
          id: 'responded',
          startDate: '2026-06-10',
          endDate: '2026-06-12',
        }),
        makeEvent({
          id: 'no-response',
          startDate: '2026-07-01',
          endDate: '2026-07-02',
        }),
        makeRsvp({ id: 'r1', eventId: 'responded', userId: 'user-1' }),
      ],
      { scope: Scope.workspace('test') }
    )

    const { upcomingEvents } = useUpcomingEvents()
    const byId = new Map(upcomingEvents.value.map((e) => [e.eventId, e]))

    expect(byId.get('responded')!.needsRsvp).toBe(false)
    expect(byId.get('no-response')!.needsRsvp).toBe(true)
  })

  it('counts attending RSVPs per event', () => {
    const pool = useObjectPoolStore()
    signIn('user-1')
    pool.importObjects(
      [
        makeEvent({
          id: 'trip',
          startDate: '2026-06-10',
          endDate: '2026-06-12',
        }),
        makeRsvp({
          id: 'r1',
          eventId: 'trip',
          userId: 'user-1',
          attending: true,
        }),
        makeRsvp({
          id: 'r2',
          eventId: 'trip',
          userId: 'user-2',
          attending: true,
        }),
        makeRsvp({
          id: 'r3',
          eventId: 'trip',
          userId: 'user-3',
          attending: false,
        }),
      ],
      { scope: Scope.workspace('test') }
    )

    const { upcomingEvents } = useUpcomingEvents()

    expect(upcomingEvents.value[0]!.attendeeCount).toBe(2)
  })
})
