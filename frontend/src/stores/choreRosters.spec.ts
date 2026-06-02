import { Scope } from '@/api/scope'
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useChoreRostersStore } from './choreRosters'
import { useObjectPoolStore } from './objectPool'
import { CommandQueuedError } from '@/stores/commandQueue'
import type { ObjectTypeMap } from '@/types/pool'
import type { ApiResponse } from '@/api/client'

function makeAssignment(
  overrides: Partial<ObjectTypeMap['choreAssignment']> = {}
): ObjectTypeMap['choreAssignment'] {
  return {
    id: 'assign-1',
    objectType: 'choreAssignment',
    choreId: 'chore-1',
    userId: 'user-1',
    date: '2026-03-10',
    pinned: true,
    note: null,
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  }
}

function okResponse<T>(data: T): ApiResponse<T> {
  return { data, status: 200 }
}

// Mutable handler so individual tests can swap out behaviour.
let enqueueImpl: () => Promise<ApiResponse<unknown>> = async () =>
  okResponse({})

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

describe('choreRosters store — updateAssignment', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    enqueueImpl = async () => okResponse({})
  })

  it('optimistically applies changes to the pool during the API call', async () => {
    const pool = useObjectPoolStore()
    pool.importObjects([makeAssignment({ note: null })], {
      scope: Scope.workspace('test'),
    })
    const store = useChoreRostersStore()

    let noteDuringCall: string | null | undefined
    enqueueImpl = async () => {
      noteDuringCall = pool.get('choreAssignment', 'assign-1')?.note
      return okResponse({})
    }

    await store.updateAssignment('roster-1', 'assign-1', {
      note: 'bring towel',
    })

    expect(noteDuringCall).toBe('bring towel')
  })

  it('rolls back the optimistic update when the API call fails', async () => {
    const pool = useObjectPoolStore()
    pool.importObjects([makeAssignment({ note: 'original note' })], {
      scope: Scope.workspace('test'),
    })
    const store = useChoreRostersStore()

    enqueueImpl = async () => {
      throw new Error('Server error')
    }

    await expect(
      store.updateAssignment('roster-1', 'assign-1', { note: 'bad change' })
    ).rejects.toThrow('Server error')

    expect(pool.get('choreAssignment', 'assign-1')?.note).toBe('original note')
    expect(pool.hasPending('choreAssignment', 'assign-1')).toBe(false)
  })

  it('keeps pending update when the request is queued offline', async () => {
    const pool = useObjectPoolStore()
    pool.importObjects([makeAssignment({ note: null })], {
      scope: Scope.workspace('test'),
    })
    const store = useChoreRostersStore()

    enqueueImpl = async () => {
      throw new CommandQueuedError()
    }

    await store.updateAssignment('roster-1', 'assign-1', {
      note: 'offline note',
    })

    expect(pool.get('choreAssignment', 'assign-1')?.note).toBe('offline note')
    expect(pool.hasPending('choreAssignment', 'assign-1')).toBe(true)
  })
})
