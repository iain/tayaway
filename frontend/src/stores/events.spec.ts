import { Scope } from '@/api/scope'
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useEventsStore } from './events'
import { useObjectPoolStore } from './objectPool'
import { CommandQueuedError } from '@/stores/commandQueue'
import type { ObjectTypeMap } from '@/types/pool'
import type { ApiResponse } from '@/api/client'

function makeEvent(
  overrides: Partial<ObjectTypeMap['event']> = {}
): ObjectTypeMap['event'] {
  return {
    id: 'evt-1',
    objectType: 'event',
    name: 'Test Event',
    description: null,
    startDate: null,
    endDate: null,
    locationName: null,
    latitude: null,
    longitude: null,
    timezone: 'Europe/Amsterdam',
    workspaceId: 'ws-1',
    userId: 'user-1',
    datePollId: null,
    rsvpIds: [],
    attendanceIds: [],
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  }
}

function okResponse<T>(data: T): ApiResponse<T> {
  return { data, status: 200 }
}

let enqueueImpl: () => Promise<ApiResponse<unknown>> = async () =>
  okResponse({ objects: [] })

vi.mock('@/stores/commandQueue', async () => {
  const actual = await vi.importActual<typeof import('@/stores/commandQueue')>(
    '@/stores/commandQueue'
  )
  return {
    ...actual,
    useCommandQueueStore: () => ({
      enqueue: vi.fn().mockImplementation(() => enqueueImpl()),
    }),
  }
})

vi.mock('@/stores/auth', () => ({
  useAuthStore: () => ({ currentUserId: 'user-1' }),
}))

vi.mock('@/stores/workspace', () => ({
  useWorkspaceStore: () => ({ currentWorkspaceId: 'ws-1' }),
}))

describe('events store', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    enqueueImpl = async () => okResponse({ objects: [] })
  })

  describe('createEvent', () => {
    it('inserts a temp event into the pool before the API call', async () => {
      const pool = useObjectPoolStore()
      const store = useEventsStore()

      let eventDuringCall: ObjectTypeMap['event'] | undefined
      enqueueImpl = async () => {
        eventDuringCall = pool.getAll('event')[0]
        return okResponse({ objects: [] })
      }

      const { eventId } = await store.createEvent({ name: 'Beach Trip' })

      expect(eventDuringCall).toBeDefined()
      expect(eventDuringCall!.name).toBe('Beach Trip')
      expect(eventDuringCall!.id).toBe(eventId)
      expect(eventDuringCall!.workspaceId).toBe('ws-1')
      expect(eventDuringCall!.userId).toBe('user-1')
    })

    it('sets optional fields to null when not provided', async () => {
      const pool = useObjectPoolStore()
      const store = useEventsStore()

      let eventDuringCall: ObjectTypeMap['event'] | undefined
      enqueueImpl = async () => {
        eventDuringCall = pool.getAll('event')[0]
        return okResponse({ objects: [] })
      }

      await store.createEvent({ name: 'Minimal Event' })

      expect(eventDuringCall!.description).toBeNull()
      expect(eventDuringCall!.startDate).toBeNull()
      expect(eventDuringCall!.endDate).toBeNull()
      expect(eventDuringCall!.locationName).toBeNull()
      expect(eventDuringCall!.latitude).toBeNull()
      expect(eventDuringCall!.longitude).toBeNull()
    })

    it('keeps the temp event when request is queued offline', async () => {
      const pool = useObjectPoolStore()
      const store = useEventsStore()

      enqueueImpl = async () => {
        throw new CommandQueuedError()
      }

      const { eventId, queued } = await store.createEvent({
        name: 'Queued Event',
      })

      expect(queued).toBe(true)
      expect(pool.get('event', eventId)).toBeDefined()
    })

    it('removes the temp event on server error', async () => {
      const pool = useObjectPoolStore()
      const store = useEventsStore()

      enqueueImpl = async () => {
        throw new Error('Server error')
      }

      await expect(store.createEvent({ name: 'Fail Event' })).rejects.toThrow(
        'Server error'
      )

      expect(pool.getAll('event')).toHaveLength(0)
      expect(store.error).toBe('Failed to create event')
    })

    it('returns queued: false on success', async () => {
      const store = useEventsStore()

      const { queued } = await store.createEvent({ name: 'Success Event' })

      expect(queued).toBe(false)
    })
  })

  describe('updateEvent', () => {
    it('optimistically applies changes to the pool during the API call', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent({ name: 'Old Name' })], {
        scope: Scope.workspace('test'),
      })
      const store = useEventsStore()

      let nameDuringCall: string | undefined
      enqueueImpl = async () => {
        nameDuringCall = pool.get('event', 'evt-1')?.name
        return okResponse({ objects: [] })
      }

      await store.updateEvent('evt-1', { name: 'New Name' })

      expect(nameDuringCall).toBe('New Name')
    })

    it('rolls back the optimistic update when the API call fails', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent({ name: 'Original' })], {
        scope: Scope.workspace('test'),
      })
      const store = useEventsStore()

      enqueueImpl = async () => {
        throw new Error('Server error')
      }

      await expect(
        store.updateEvent('evt-1', { name: 'Changed' })
      ).rejects.toThrow()

      expect(pool.get('event', 'evt-1')?.name).toBe('Original')
      expect(pool.hasPending('event', 'evt-1')).toBe(false)
      expect(store.error).toBe('Failed to update event')
    })

    it('keeps pending update when queued offline', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent({ name: 'Original' })], {
        scope: Scope.workspace('test'),
      })
      const store = useEventsStore()

      enqueueImpl = async () => {
        throw new CommandQueuedError()
      }

      await store.updateEvent('evt-1', { name: 'Changed' })

      expect(pool.get('event', 'evt-1')?.name).toBe('Changed')
      expect(pool.hasPending('event', 'evt-1')).toBe(true)
    })
  })

  describe('deleteEvent', () => {
    it('optimistically removes the event from the pool', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent()], { scope: Scope.workspace('test') })
      const store = useEventsStore()

      let presentDuringCall: boolean | undefined
      enqueueImpl = async () => {
        presentDuringCall = pool.get('event', 'evt-1') !== undefined
        return okResponse({ objects: [] })
      }

      await store.deleteEvent('evt-1')

      expect(presentDuringCall).toBe(false)
      expect(pool.get('event', 'evt-1')).toBeUndefined()
    })

    it('restores the event when the API call fails', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent()], { scope: Scope.workspace('test') })
      const store = useEventsStore()

      enqueueImpl = async () => {
        throw new Error('Server error')
      }

      await expect(store.deleteEvent('evt-1')).rejects.toThrow('Server error')

      expect(pool.get('event', 'evt-1')).toBeDefined()
      expect(store.error).toBe('Failed to delete event')
    })

    it('keeps the event removed when queued offline', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent()], { scope: Scope.workspace('test') })
      const store = useEventsStore()

      enqueueImpl = async () => {
        throw new CommandQueuedError()
      }

      await store.deleteEvent('evt-1')

      expect(pool.get('event', 'evt-1')).toBeUndefined()
    })
  })

  describe('$reset', () => {
    it('clears loading and error state', async () => {
      const store = useEventsStore()

      enqueueImpl = async () => {
        throw new Error('fail')
      }
      try {
        await store.createEvent({ name: 'x' })
      } catch {
        // expected
      }

      expect(store.error).toBe('Failed to create event')

      store.$reset()

      expect(store.loading).toBe(false)
      expect(store.error).toBeNull()
    })
  })
})
