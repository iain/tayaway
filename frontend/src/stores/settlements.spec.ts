import { describe, it, expect, beforeEach, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useSettlementsStore } from './settlements'
import { useObjectPoolStore } from './objectPool'
import { CommandQueuedError } from '@/stores/commandQueue'
import type { ObjectTypeMap } from '@/types/pool'
import type { ApiResponse } from '@/api/client'

function makeSettlement(
  overrides: Partial<ObjectTypeMap['settlement']> = {}
): ObjectTypeMap['settlement'] {
  return {
    id: 'settle-1',
    objectType: 'settlement',
    eventId: 'evt-1',
    userId: 'user-1',
    transferIds: [],
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

describe('settlements store — deleteSettlement', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    enqueueImpl = async () => okResponse({})
  })

  it('optimistically removes the settlement from the pool', async () => {
    const pool = useObjectPoolStore()
    pool.importObjects([makeSettlement()])
    const store = useSettlementsStore()

    let presentDuringCall = false
    enqueueImpl = async () => {
      presentDuringCall = pool.get('settlement', 'settle-1') !== undefined
      return okResponse({})
    }

    await store.deleteSettlement('settle-1')

    // Should be removed during AND after the call
    expect(presentDuringCall).toBe(false)
    expect(pool.get('settlement', 'settle-1')).toBeUndefined()
  })

  it('restores the settlement on server error', async () => {
    const pool = useObjectPoolStore()
    pool.importObjects([makeSettlement({ eventId: 'evt-1' })])
    const store = useSettlementsStore()

    enqueueImpl = async () => {
      throw new Error('Server error')
    }

    await expect(store.deleteSettlement('settle-1')).rejects.toThrow(
      'Server error'
    )

    expect(pool.get('settlement', 'settle-1')).toBeDefined()
    expect(pool.get('settlement', 'settle-1')?.eventId).toBe('evt-1')
  })

  it('keeps the settlement removed on CommandQueuedError', async () => {
    const pool = useObjectPoolStore()
    pool.importObjects([makeSettlement()])
    const store = useSettlementsStore()

    enqueueImpl = async () => {
      throw new CommandQueuedError()
    }

    await store.deleteSettlement('settle-1')

    expect(pool.get('settlement', 'settle-1')).toBeUndefined()
  })

  it('sets error message on server error', async () => {
    const pool = useObjectPoolStore()
    pool.importObjects([makeSettlement()])
    const store = useSettlementsStore()

    enqueueImpl = async () => {
      throw new Error('500')
    }

    await expect(store.deleteSettlement('settle-1')).rejects.toThrow()
    expect(store.error).toBe('Failed to delete settlement')
  })
})
