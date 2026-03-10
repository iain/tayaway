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
    id: 'settlement-1',
    objectType: 'settlement',
    eventId: 'event-1',
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

  it('removes the settlement from the pool immediately (optimistic)', async () => {
    const pool = useObjectPoolStore()
    pool.importObjects([makeSettlement()])
    const store = useSettlementsStore()

    let poolHadSettlementDuringCall = true
    enqueueImpl = async () => {
      poolHadSettlementDuringCall =
        pool.get('settlement', 'settlement-1') !== undefined
      return okResponse(null)
    }

    await store.deleteSettlement('settlement-1')

    expect(poolHadSettlementDuringCall).toBe(false)
    expect(pool.get('settlement', 'settlement-1')).toBeUndefined()
  })

  it('restores the settlement in the pool on server error', async () => {
    const pool = useObjectPoolStore()
    pool.importObjects([makeSettlement()])
    const store = useSettlementsStore()

    enqueueImpl = async () => {
      throw new Error('Server error')
    }

    await expect(store.deleteSettlement('settlement-1')).rejects.toThrow(
      'Server error'
    )

    expect(pool.get('settlement', 'settlement-1')).toBeDefined()
  })

  it('keeps the settlement removed when the request is queued offline', async () => {
    const pool = useObjectPoolStore()
    pool.importObjects([makeSettlement()])
    const store = useSettlementsStore()

    enqueueImpl = async () => {
      throw new CommandQueuedError()
    }

    const result = await store.deleteSettlement('settlement-1')

    expect(result).toEqual({ queued: true })
    expect(pool.get('settlement', 'settlement-1')).toBeUndefined()
  })
})
