import { Scope } from '@/api/scope'
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { ref } from 'vue'
import { useEventsNeedingRsvp } from './useEventsNeedingRsvp'
import { useObjectPoolStore } from '@/stores'
import { makeAttendance, makeEvent } from '@/test/factories'

// The composable pulls currentUserId out via storeToRefs, so the mocked
// store must already hold a ref.
vi.mock('@/stores/auth', () => ({
  useAuthStore: () => ({ currentUserId: ref('user-1') }),
}))

vi.mock('pinia', async () => {
  const actual = await vi.importActual<typeof import('pinia')>('pinia')
  return {
    ...actual,
    storeToRefs: (store: Record<string, unknown>) => store,
  }
})

describe('useEventsNeedingRsvp', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  function seedEventWithAttendance(
    eventId: string,
    status: 'pending' | 'going' | 'declined' | null
  ) {
    const pool = useObjectPoolStore()
    const objects = [
      makeEvent({
        id: eventId,
        name: `Event ${eventId}`,
        startDate: '2099-07-01',
        endDate: '2099-07-07',
      }),
    ]
    if (status) {
      objects.push(
        makeAttendance({
          id: `att-${eventId}`,
          eventId,
          userId: 'user-1',
          status,
          days: null,
        }) as never
      )
    }
    pool.importObjects(objects, { scope: Scope.workspace('test') })
  }

  it('lists events without an attendance row for the user', () => {
    seedEventWithAttendance('evt-none', null)

    const { eventsNeedingRsvp } = useEventsNeedingRsvp()

    expect(eventsNeedingRsvp.value.map((e) => e.eventId)).toEqual(['evt-none'])
  })

  it('treats a pending row as unanswered — the second form of "no response" after a date reset', () => {
    seedEventWithAttendance('evt-pending', 'pending')

    const { eventsNeedingRsvp } = useEventsNeedingRsvp()

    expect(eventsNeedingRsvp.value.map((e) => e.eventId)).toEqual([
      'evt-pending',
    ])
  })

  it('skips events the user has answered, either way', () => {
    seedEventWithAttendance('evt-going', 'going')
    seedEventWithAttendance('evt-declined', 'declined')

    const { eventsNeedingRsvp } = useEventsNeedingRsvp()

    expect(eventsNeedingRsvp.value).toEqual([])
  })
})
