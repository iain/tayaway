import { Scope } from '@/api/scope'
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useMutation } from './useMutation'
import { useObjectPoolStore } from '@/stores/objectPool'
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
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  }
}

function okResponse<T>(data: T): ApiResponse<T> {
  return { data, status: 200 }
}

// Mock commandQueue — useMutation only needs the store reference passed to fn()
vi.mock('@/stores/commandQueue', async () => {
  const actual = await vi.importActual<typeof import('@/stores/commandQueue')>(
    '@/stores/commandQueue'
  )
  return {
    ...actual,
    useCommandQueueStore: () => ({}),
  }
})

describe('useMutation', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  describe('mutate', () => {
    it('returns data on success', async () => {
      const { mutate, loading, error } = useMutation()

      const result = await mutate('fail msg', async () =>
        okResponse({ ok: true })
      )

      expect(result).toEqual({ queued: false, data: { ok: true } })
      expect(loading.value).toBe(false)
      expect(error.value).toBeNull()
    })

    it('returns queued result on CommandQueuedError', async () => {
      const { mutate, loading, error } = useMutation()

      const result = await mutate('fail msg', async () => {
        throw new CommandQueuedError()
      })

      expect(result).toEqual({ queued: true })
      expect(loading.value).toBe(false)
      expect(error.value).toBeNull()
    })

    it('sets error message and rethrows on server error', async () => {
      const { mutate, error } = useMutation()
      const serverError = new Error('500 Internal Server Error')

      await expect(
        mutate('Something went wrong', async () => {
          throw serverError
        })
      ).rejects.toThrow(serverError)

      expect(error.value).toBe('Something went wrong')
    })

    it('sets loading during execution', async () => {
      const { mutate, loading } = useMutation()
      let loadingDuringCall = false

      await mutate('fail', async () => {
        loadingDuringCall = loading.value
        return okResponse(null)
      })

      expect(loadingDuringCall).toBe(true)
      expect(loading.value).toBe(false)
    })
  })

  describe('create', () => {
    it('inserts temp object into pool then returns data on success', async () => {
      const pool = useObjectPoolStore()
      const { create } = useMutation()
      const temp = makeEvent({ id: 'temp-1', name: 'New Event' })

      const result = await create('fail', temp, async () =>
        okResponse({ id: 'real-1' })
      )

      expect(result).toEqual({ queued: false, data: { id: 'real-1' } })
      // Temp object is in pool (server response would normally replace it)
      expect(pool.get('event', 'temp-1')?.name).toBe('New Event')
    })

    it('marks temp object with isTemp flag so it survives replaceObjects during sync', async () => {
      const pool = useObjectPoolStore()
      const { create } = useMutation()
      const temp = makeEvent({ id: 'temp-1', name: 'Queued Event' })

      await create('fail', temp, async () => okResponse({ id: 'real-1' }))

      // Simulate a full sync that replaces all objects without the temp ID
      pool.replaceScope(Scope.workspace('test'), [
        makeEvent({ id: 'other-1', name: 'Server Event' }),
      ])

      // Temp object must survive the sync because it was flagged as isTemp
      expect(pool.get('event', 'temp-1')?.name).toBe('Queued Event')
    })

    it('keeps temp object on CommandQueuedError', async () => {
      const pool = useObjectPoolStore()
      const { create } = useMutation()
      const temp = makeEvent({ id: 'temp-1' })

      const result = await create('fail', temp, async () => {
        throw new CommandQueuedError()
      })

      expect(result).toEqual({ queued: true })
      expect(pool.get('event', 'temp-1')).toBeDefined()
    })

    it('removes temp object on server error', async () => {
      const pool = useObjectPoolStore()
      const { create } = useMutation()
      const temp = makeEvent({ id: 'temp-1' })

      await expect(
        create('fail', temp, async () => {
          // Verify temp was added before the error
          expect(pool.get('event', 'temp-1')).toBeDefined()
          throw new Error('Server error')
        })
      ).rejects.toThrow('Server error')

      expect(pool.get('event', 'temp-1')).toBeUndefined()
    })
  })

  describe('update', () => {
    it('adds pending update and returns data on success', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent({ name: 'Original' })], {
        scope: Scope.workspace('test'),
      })
      const { update } = useMutation()

      // During the API call the pending update should be visible
      let nameDuringCall: string | undefined
      const result = await update(
        'fail',
        'event',
        'evt-1',
        { name: 'Updated' },
        async () => {
          nameDuringCall = pool.get('event', 'evt-1')?.name
          return okResponse(null)
        }
      )

      expect(nameDuringCall).toBe('Updated')
      expect(result).toEqual({ queued: false, data: null })
    })

    // importObjects only clears overlays the server response postdates; a
    // client clock running ahead of the server defeats that, and the stale
    // overlay then masks other users' edits. A direct success IS the
    // confirmation of this change, so the overlay is dropped explicitly.
    it('clears the pending overlay on success even when the client clock is ahead of the server', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent({ name: 'Original' })], {
        scope: Scope.workspace('test'),
      })
      const { update } = useMutation()

      await update('fail', 'event', 'evt-1', { name: 'Updated' }, async () => {
        // The command queue imports the server confirmation before enqueue
        // resolves; its updatedAt (server clock) trails the client's Date.now()
        pool.importObjects(
          [
            makeEvent({
              name: 'Updated',
              updatedAt: '2026-01-02T00:00:00.000Z',
            }),
          ],
          { scope: Scope.workspace('test') }
        )
        return okResponse(null)
      })

      expect(pool.hasPending('event', 'evt-1')).toBe(false)
      expect(pool.get('event', 'evt-1')?.name).toBe('Updated')
    })

    it('keeps pending update on CommandQueuedError', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent({ name: 'Original' })], {
        scope: Scope.workspace('test'),
      })
      const { update } = useMutation()

      await update('fail', 'event', 'evt-1', { name: 'Pending' }, async () => {
        throw new CommandQueuedError()
      })

      expect(pool.get('event', 'evt-1')?.name).toBe('Pending')
      expect(pool.hasPending('event', 'evt-1')).toBe(true)
    })

    it('rolls back pending update on server error', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent({ name: 'Original' })], {
        scope: Scope.workspace('test'),
      })
      const { update } = useMutation()

      await expect(
        update('fail', 'event', 'evt-1', { name: 'Bad Update' }, async () => {
          throw new Error('Validation error')
        })
      ).rejects.toThrow('Validation error')

      expect(pool.get('event', 'evt-1')?.name).toBe('Original')
      expect(pool.hasPending('event', 'evt-1')).toBe(false)
    })
  })

  describe('destroy', () => {
    it('removes object from pool and returns data on success', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent()], { scope: Scope.workspace('test') })
      const { destroy } = useMutation()

      const result = await destroy('fail', 'event', 'evt-1', async () =>
        okResponse(null)
      )

      expect(result).toEqual({ queued: false, data: null })
      expect(pool.get('event', 'evt-1')).toBeUndefined()
    })

    it('keeps object removed on CommandQueuedError', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent()], { scope: Scope.workspace('test') })
      const { destroy } = useMutation()

      await destroy('fail', 'event', 'evt-1', async () => {
        throw new CommandQueuedError()
      })

      expect(pool.get('event', 'evt-1')).toBeUndefined()
    })

    it('restores object on server error', async () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent({ name: 'Keep Me' })], {
        scope: Scope.workspace('test'),
      })
      const { destroy } = useMutation()

      await expect(
        destroy('fail', 'event', 'evt-1', async () => {
          // Object should be removed during call
          expect(pool.get('event', 'evt-1')).toBeUndefined()
          throw new Error('Cannot delete')
        })
      ).rejects.toThrow('Cannot delete')

      expect(pool.get('event', 'evt-1')?.name).toBe('Keep Me')
    })

    it('does not restore if object was not in pool', async () => {
      const pool = useObjectPoolStore()
      const { destroy } = useMutation()

      await expect(
        destroy('fail', 'event', 'nonexistent', async () => {
          throw new Error('Not found')
        })
      ).rejects.toThrow('Not found')

      expect(pool.get('event', 'nonexistent')).toBeUndefined()
    })

    describe('cascade behaviour', () => {
      function makeTaskList(
        overrides: Partial<ObjectTypeMap['taskList']> = {}
      ): ObjectTypeMap['taskList'] {
        return {
          id: 'list-1',
          objectType: 'taskList',
          workspaceId: 'ws-1',
          userId: 'user-1',
          name: 'Shopping',
          position: 1,
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
          ...overrides,
        }
      }

      function makeTaskItem(
        overrides: Partial<ObjectTypeMap['taskItem']> = {}
      ): ObjectTypeMap['taskItem'] {
        return {
          id: 'item-1',
          objectType: 'taskItem',
          taskListId: 'list-1',
          userId: null,
          content: 'Milk',
          completedAt: null,
          position: 1,
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
          ...overrides,
        }
      }

      it('removes child objects from the pool before the API call', async () => {
        const pool = useObjectPoolStore()
        pool.importObjects(
          [
            makeTaskList(),
            makeTaskItem({ id: 'item-1', taskListId: 'list-1' }),
            makeTaskItem({ id: 'item-2', taskListId: 'list-1' }),
          ],
          { scope: Scope.workspace('test') }
        )
        const { destroy } = useMutation()

        let item1DuringCall: boolean | undefined
        let item2DuringCall: boolean | undefined
        await destroy('fail', 'taskList', 'list-1', async () => {
          item1DuringCall = pool.get('taskItem', 'item-1') !== undefined
          item2DuringCall = pool.get('taskItem', 'item-2') !== undefined
          return okResponse(null)
        })

        expect(item1DuringCall).toBe(false)
        expect(item2DuringCall).toBe(false)
        expect(pool.get('taskItem', 'item-1')).toBeUndefined()
        expect(pool.get('taskItem', 'item-2')).toBeUndefined()
      })

      it('does not remove child objects belonging to a different parent', async () => {
        const pool = useObjectPoolStore()
        pool.importObjects(
          [
            makeTaskList({ id: 'list-1' }),
            makeTaskList({ id: 'list-2' }),
            makeTaskItem({ id: 'item-1', taskListId: 'list-1' }),
            makeTaskItem({ id: 'item-2', taskListId: 'list-2' }),
          ],
          { scope: Scope.workspace('test') }
        )
        const { destroy } = useMutation()

        await destroy('fail', 'taskList', 'list-1', async () =>
          okResponse(null)
        )

        expect(pool.get('taskList', 'list-2')).toBeDefined()
        expect(pool.get('taskItem', 'item-2')).toBeDefined()
      })

      it('restores all children on server error', async () => {
        const pool = useObjectPoolStore()
        pool.importObjects(
          [
            makeTaskList(),
            makeTaskItem({ id: 'item-1', taskListId: 'list-1' }),
            makeTaskItem({ id: 'item-2', taskListId: 'list-1' }),
          ],
          { scope: Scope.workspace('test') }
        )
        const { destroy } = useMutation()

        await expect(
          destroy('fail', 'taskList', 'list-1', async () => {
            throw new Error('Server error')
          })
        ).rejects.toThrow('Server error')

        expect(pool.get('taskList', 'list-1')).toBeDefined()
        expect(pool.get('taskItem', 'item-1')).toBeDefined()
        expect(pool.get('taskItem', 'item-2')).toBeDefined()
      })

      it('keeps children removed when queued offline', async () => {
        const pool = useObjectPoolStore()
        pool.importObjects(
          [
            makeTaskList(),
            makeTaskItem({ id: 'item-1', taskListId: 'list-1' }),
          ],
          { scope: Scope.workspace('test') }
        )
        const { destroy } = useMutation()

        const result = await destroy('fail', 'taskList', 'list-1', async () => {
          throw new CommandQueuedError()
        })

        expect(result).toEqual({ queued: true })
        expect(pool.get('taskList', 'list-1')).toBeUndefined()
        expect(pool.get('taskItem', 'item-1')).toBeUndefined()
      })
    })
  })
})
