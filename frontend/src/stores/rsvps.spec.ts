import { Scope } from '@/api/scope'
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useRsvpsStore } from './rsvps'
import { useObjectPoolStore } from './objectPool'
import { useWorkspaceStore } from './workspace'
import { CommandQueuedError } from '@/stores/commandQueue'
import type { ObjectTypeMap } from '@/types/pool'
import type { ApiResponse } from '@/api/client'

function makeRsvp(
  overrides: Partial<ObjectTypeMap['rsvp']> = {}
): ObjectTypeMap['rsvp'] {
  return {
    id: 'rsvp-1',
    objectType: 'rsvp',
    eventId: 'evt-1',
    userId: 'user-1',
    createdByUserId: null,
    attending: true,
    attendance: null,
    startDate: null,
    endDate: null,
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

describe('rsvps store', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    // Optimistic temp RSVPs are scope-less objects; useMutation tags them
    // with the active workspace's scope and throws if none is set.
    localStorage.setItem('current_workspace_id', 'test')
    useWorkspaceStore().initialize(['test'])
    enqueueImpl = async () => okResponse({ objects: [] })
  })

  describe('submitRsvp — new RSVP', () => {
    it('creates a temp RSVP in the pool optimistically', async () => {
      const pool = useObjectPoolStore()
      const store = useRsvpsStore()

      let rsvpDuringCall: ObjectTypeMap['rsvp'] | undefined
      enqueueImpl = async () => {
        rsvpDuringCall = pool.getAll('rsvp')[0]
        return okResponse({ objects: [] })
      }

      const { rsvpId } = await store.submitRsvp('evt-1', true)

      expect(rsvpDuringCall).toBeDefined()
      expect(rsvpDuringCall!.eventId).toBe('evt-1')
      expect(rsvpDuringCall!.userId).toBe('user-1')
      expect(rsvpDuringCall!.attending).toBe(true)
      expect(rsvpDuringCall!.id).toBe(rsvpId)
    })

    it('sets date fields to null when not provided', async () => {
      const pool = useObjectPoolStore()
      const store = useRsvpsStore()

      let rsvpDuringCall: ObjectTypeMap['rsvp'] | undefined
      enqueueImpl = async () => {
        rsvpDuringCall = pool.getAll('rsvp')[0]
        return okResponse({ objects: [] })
      }

      await store.submitRsvp('evt-1', true)

      expect(rsvpDuringCall!.startDate).toBeNull()
      expect(rsvpDuringCall!.endDate).toBeNull()
    })

    it('keeps the temp RSVP when request is queued offline', async () => {
      const pool = useObjectPoolStore()
      const store = useRsvpsStore()

      enqueueImpl = async () => {
        throw new CommandQueuedError()
      }

      const { rsvpId, queued } = await store.submitRsvp('evt-1', false)

      expect(queued).toBe(true)
      expect(pool.get('rsvp', rsvpId)).toBeDefined()
    })

    it('removes the temp RSVP on server error', async () => {
      const pool = useObjectPoolStore()
      const store = useRsvpsStore()

      enqueueImpl = async () => {
        throw new Error('Server error')
      }

      await expect(store.submitRsvp('evt-1', true)).rejects.toThrow(
        'Server error'
      )

      expect(pool.getAll('rsvp')).toHaveLength(0)
      expect(store.error).toBe('Failed to submit RSVP')
    })

    it('removes the phantom temp RSVP when server returns a different id', async () => {
      const pool = useObjectPoolStore()
      const store = useRsvpsStore()

      // Server merged with an existing RSVP and returned a different id
      const serverRsvp = makeRsvp({ id: 'rsvp-server', userId: 'user-1' })
      enqueueImpl = async () => okResponse({ objects: [serverRsvp] })

      const { rsvpId } = await store.submitRsvp('evt-1', true)

      // The temp object with the client-generated id is removed
      expect(pool.get('rsvp', rsvpId)).toBeUndefined()
    })

    it('does not remove the RSVP when server returns the same id', async () => {
      const pool = useObjectPoolStore()
      const store = useRsvpsStore()

      let capturedId: string | undefined
      enqueueImpl = async () => {
        capturedId = pool.getAll('rsvp')[0]?.id
        return okResponse({ objects: [makeRsvp({ id: capturedId! })] })
      }

      const { rsvpId } = await store.submitRsvp('evt-1', true)

      // The RSVP stays in the pool when IDs match
      expect(pool.get('rsvp', rsvpId)).toBeDefined()
    })
  })

  describe('submitRsvp — existing RSVP (update)', () => {
    it('optimistically updates the existing RSVP attending status', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeRsvp({ attending: true })], {
        scope: Scope.workspace('test'),
      })
      const store = useRsvpsStore()

      let attendingDuringCall: boolean | undefined
      enqueueImpl = async () => {
        attendingDuringCall = pool.get('rsvp', 'rsvp-1')?.attending
        return okResponse({ objects: [] })
      }

      const result = await store.submitRsvp('evt-1', false)

      expect(attendingDuringCall).toBe(false)
      expect(result.rsvpId).toBe('rsvp-1')
      expect(result.queued).toBe(false)
    })

    it('optimistically updates the attendance day set and hull', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects(
        [makeRsvp({ attendance: null, startDate: null, endDate: null })],
        { scope: Scope.workspace('test') }
      )
      const store = useRsvpsStore()

      let attendanceDuringCall: string[] | null | undefined
      let startDuringCall: string | null | undefined
      enqueueImpl = async () => {
        attendanceDuringCall = pool.get('rsvp', 'rsvp-1')?.attendance
        startDuringCall = pool.get('rsvp', 'rsvp-1')?.startDate
        return okResponse({ objects: [] })
      }

      await store.submitRsvp('evt-1', true, {
        attendance: ['2026-03-03', '2026-03-01'],
      })

      // Sorted day set, with the contiguous hull mirrored onto startDate.
      expect(attendanceDuringCall).toEqual(['2026-03-01', '2026-03-03'])
      expect(startDuringCall).toBe('2026-03-01')
    })

    it('keeps pending update when queued offline', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeRsvp({ attending: true })], {
        scope: Scope.workspace('test'),
      })
      const store = useRsvpsStore()

      enqueueImpl = async () => {
        throw new CommandQueuedError()
      }

      const result = await store.submitRsvp('evt-1', false)

      expect(result.queued).toBe(true)
      expect(pool.get('rsvp', 'rsvp-1')?.attending).toBe(false)
      expect(pool.hasPending('rsvp', 'rsvp-1')).toBe(true)
    })

    it('rolls back pending update on server error', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeRsvp({ attending: true })], {
        scope: Scope.workspace('test'),
      })
      const store = useRsvpsStore()

      enqueueImpl = async () => {
        throw new Error('Server error')
      }

      await expect(store.submitRsvp('evt-1', false)).rejects.toThrow()

      expect(pool.get('rsvp', 'rsvp-1')?.attending).toBe(true)
      expect(pool.hasPending('rsvp', 'rsvp-1')).toBe(false)
    })
  })

  describe('deleteRsvp', () => {
    it('optimistically removes the RSVP from the pool', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeRsvp()], { scope: Scope.workspace('test') })
      const store = useRsvpsStore()

      let presentDuringCall: boolean | undefined
      enqueueImpl = async () => {
        presentDuringCall = pool.get('rsvp', 'rsvp-1') !== undefined
        return okResponse({ objects: [] })
      }

      await store.deleteRsvp('evt-1', 'rsvp-1')

      expect(presentDuringCall).toBe(false)
      expect(pool.get('rsvp', 'rsvp-1')).toBeUndefined()
    })

    it('restores the RSVP when the API call fails', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeRsvp()], { scope: Scope.workspace('test') })
      const store = useRsvpsStore()

      enqueueImpl = async () => {
        throw new Error('Server error')
      }

      await expect(store.deleteRsvp('evt-1', 'rsvp-1')).rejects.toThrow(
        'Server error'
      )

      expect(pool.get('rsvp', 'rsvp-1')).toBeDefined()
      expect(store.error).toBe('Failed to delete RSVP')
    })

    it('keeps the RSVP removed when queued offline', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeRsvp()], { scope: Scope.workspace('test') })
      const store = useRsvpsStore()

      enqueueImpl = async () => {
        throw new CommandQueuedError()
      }

      await store.deleteRsvp('evt-1', 'rsvp-1')

      expect(pool.get('rsvp', 'rsvp-1')).toBeUndefined()
    })
  })

  describe('$reset', () => {
    it('clears loading and error state', async () => {
      const store = useRsvpsStore()

      enqueueImpl = async () => {
        throw new Error('fail')
      }
      try {
        await store.submitRsvp('evt-1', true)
      } catch {
        // expected
      }

      expect(store.error).toBe('Failed to submit RSVP')

      store.$reset()

      expect(store.loading).toBe(false)
      expect(store.error).toBeNull()
    })
  })
})
