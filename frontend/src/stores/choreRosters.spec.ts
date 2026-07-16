import { Scope } from '@/api/scope'
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useChoreRostersStore } from './choreRosters'
import { useObjectPoolStore } from './objectPool'
import { CommandQueuedError } from '@/stores/commandQueue'
import type { ObjectTypeMap } from '@/types/pool'
import type { ApiResponse } from '@/api/client'
import { makeChore } from '@/test/factories'

function makeAssignment(
  overrides: Partial<ObjectTypeMap['choreAssignment']> = {}
): ObjectTypeMap['choreAssignment'] {
  return {
    id: 'assign-1',
    objectType: 'choreAssignment',
    choreId: 'chore-1',
    attendanceId: 'att-1',
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

// Mutable handler so individual tests can swap out behaviour. Receives the
// enqueue arguments (method, path, body) so tests can assert the request.
let enqueueImpl: (
  ...args: unknown[]
) => Promise<ApiResponse<unknown>> = async () => okResponse({})

vi.mock('@/stores/commandQueue', async () => {
  const actual = await vi.importActual<typeof import('@/stores/commandQueue')>(
    '@/stores/commandQueue'
  )
  return {
    ...actual,
    useCommandQueueStore: () => ({
      enqueue: vi
        .fn()
        .mockImplementation((...args: unknown[]) => enqueueImpl(...args)),
    }),
  }
})

vi.mock('@/stores/auth', () => ({
  useAuthStore: () => ({ currentUserId: 'user-1' }),
}))

vi.mock('@/stores/workspace', () => ({
  useWorkspaceStore: () => ({ currentWorkspaceId: 'ws-1' }),
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

describe('choreRosters store — createAssignment', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    enqueueImpl = async () => okResponse({})
  })

  it('sends attendance_id and seeds the optimistic row with both ids', async () => {
    const pool = useObjectPoolStore()
    const store = useChoreRostersStore()

    let body: Record<string, unknown> | undefined
    let optimistic: ObjectTypeMap['choreAssignment'] | undefined
    enqueueImpl = async (...args: unknown[]) => {
      body = args[2] as Record<string, unknown>
      optimistic = pool.get('choreAssignment', body.id as string)
      return okResponse({})
    }

    await store.createAssignment(
      'roster-1',
      'chore-1',
      { attendanceId: 'att-2', userId: 'user-2' },
      '2026-03-11'
    )

    expect(body).toMatchObject({
      chore_id: 'chore-1',
      attendance_id: 'att-2',
      date: '2026-03-11',
    })
    expect(body).not.toHaveProperty('user_id')
    expect(optimistic).toMatchObject({
      attendanceId: 'att-2',
      userId: 'user-2',
    })
  })
})

describe('choreRosters store — reassign via updateAssignment', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    enqueueImpl = async () => okResponse({})
  })

  it('sends attendance_id only, applying both ids optimistically', async () => {
    const pool = useObjectPoolStore()
    pool.importObjects([makeAssignment()], {
      scope: Scope.workspace('test'),
    })
    const store = useChoreRostersStore()

    let body: Record<string, unknown> | undefined
    let during: ObjectTypeMap['choreAssignment'] | undefined
    enqueueImpl = async (...args: unknown[]) => {
      body = args[2] as Record<string, unknown>
      during = pool.get('choreAssignment', 'assign-1')
      return okResponse({})
    }

    await store.updateAssignment('roster-1', 'assign-1', {
      attendanceId: 'att-2',
      userId: 'user-2',
    })

    expect(body).toEqual({ attendance_id: 'att-2' })
    expect(during).toMatchObject({ attendanceId: 'att-2', userId: 'user-2' })
  })
})

describe('choreRosters store — addChore', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    enqueueImpl = async () => okResponse({})
  })

  it('sends the time in the request body and the optimistic chore', async () => {
    const pool = useObjectPoolStore()
    const store = useChoreRostersStore()

    let body: Record<string, unknown> | undefined
    let timeDuringCall: string | null | undefined
    enqueueImpl = async (...args: unknown[]) => {
      body = args[2] as Record<string, unknown>
      timeDuringCall = (body.id &&
        pool.get('chore', body.id as string)?.time) as string | null
      return okResponse({})
    }

    await store.addChore('roster-1', 'Cooking', 2, '18:00')

    expect(body).toMatchObject({
      name: 'Cooking',
      people_per_day: 2,
      time: '18:00',
    })
    expect(timeDuringCall).toBe('18:00')
  })

  it('omits the time when none is given', async () => {
    const store = useChoreRostersStore()

    let body: Record<string, unknown> | undefined
    enqueueImpl = async (...args: unknown[]) => {
      body = args[2] as Record<string, unknown>
      return okResponse({})
    }

    await store.addChore('roster-1', 'Cooking', 1)

    expect(body?.time).toBeUndefined()
  })

  it('sends midnight (a falsy-looking but valid time)', async () => {
    const store = useChoreRostersStore()

    let body: Record<string, unknown> | undefined
    enqueueImpl = async (...args: unknown[]) => {
      body = args[2] as Record<string, unknown>
      return okResponse({})
    }

    await store.addChore('roster-1', 'Cooking', 1, '00:00')

    expect(body?.time).toBe('00:00')
  })
})

describe('choreRosters store — updateChore time', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    enqueueImpl = async () => okResponse({})
  })

  it('sends a new time and applies it optimistically', async () => {
    const pool = useObjectPoolStore()
    pool.importObjects([makeChore({ id: 'chore-1', time: null })], {
      scope: Scope.workspace('test'),
    })
    const store = useChoreRostersStore()

    let body: Record<string, unknown> | undefined
    let timeDuringCall: string | null | undefined
    enqueueImpl = async (...args: unknown[]) => {
      body = args[2] as Record<string, unknown>
      timeDuringCall = pool.get('chore', 'chore-1')?.time
      return okResponse({})
    }

    await store.updateChore('roster-1', 'chore-1', { time: '09:00' })

    expect(body).toMatchObject({ time: '09:00' })
    expect(timeDuringCall).toBe('09:00')
  })

  it('clears the time by sending blank', async () => {
    const pool = useObjectPoolStore()
    pool.importObjects([makeChore({ id: 'chore-1', time: '18:00' })], {
      scope: Scope.workspace('test'),
    })
    const store = useChoreRostersStore()

    let body: Record<string, unknown> | undefined
    let timeDuringCall: string | null | undefined
    enqueueImpl = async (...args: unknown[]) => {
      body = args[2] as Record<string, unknown>
      timeDuringCall = pool.get('chore', 'chore-1')?.time
      return okResponse({})
    }

    await store.updateChore('roster-1', 'chore-1', { time: null })

    expect(body).toMatchObject({ time: '' })
    expect(timeDuringCall).toBeNull()
  })

  it('omits time from the request when only other fields change', async () => {
    const pool = useObjectPoolStore()
    pool.importObjects([makeChore({ id: 'chore-1', time: '18:00' })], {
      scope: Scope.workspace('test'),
    })
    const store = useChoreRostersStore()

    let body: Record<string, unknown> | undefined
    enqueueImpl = async (...args: unknown[]) => {
      body = args[2] as Record<string, unknown>
      return okResponse({})
    }

    await store.updateChore('roster-1', 'chore-1', { name: 'Renamed' })

    expect(body).not.toHaveProperty('time')
  })
})
