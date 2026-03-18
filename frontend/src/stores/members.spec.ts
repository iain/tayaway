import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useMembersStore } from './members'

vi.mock('@/stores/workspace', () => ({
  useWorkspaceStore: () => ({ currentWorkspaceId: 'ws-1' }),
}))

vi.mock('@/stores/objectPool', () => ({
  useObjectPoolStore: () => ({
    getAll: () => [],
    importObjects: vi.fn(),
    remove: vi.fn(),
  }),
}))

vi.mock('@/stores/notifications', () => ({
  useNotificationsStore: () => ({ showError: vi.fn() }),
}))

// Mutable mock so individual tests can swap behaviour
let apiGetImpl: () => Promise<unknown> = async () => ({ objects: [] })

vi.mock('@/api/client', async () => {
  const actual =
    await vi.importActual<typeof import('@/api/client')>('@/api/client')
  return {
    ...actual,
    api: {
      get: vi.fn().mockImplementation(() => apiGetImpl()),
    },
  }
})

describe('members store — fetchInvites', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    apiGetImpl = async () => ({ data: { objects: [] }, status: 200 })
    vi.spyOn(console, 'error').mockImplementation(() => undefined)
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('silently ignores 403 errors', async () => {
    apiGetImpl = async () => {
      const err: { message: string; status: number } = {
        message: 'Forbidden',
        status: 403,
      }
      throw err
    }

    const store = useMembersStore()
    await expect(store.fetchInvites()).resolves.toBeUndefined()
    expect(console.error).not.toHaveBeenCalled()
  })

  it('logs non-403 errors to console.error', async () => {
    apiGetImpl = async () => {
      const err: { message: string; status: number } = {
        message: 'Internal Server Error',
        status: 500,
      }
      throw err
    }

    const store = useMembersStore()
    await store.fetchInvites()

    expect(console.error).toHaveBeenCalledWith(
      'Failed to fetch invites',
      expect.objectContaining({ status: 500 })
    )
  })

  it('logs network errors (no status) to console.error', async () => {
    apiGetImpl = async () => {
      throw new TypeError('Failed to fetch')
    }

    const store = useMembersStore()
    await store.fetchInvites()

    expect(console.error).toHaveBeenCalledWith(
      'Failed to fetch invites',
      expect.any(TypeError)
    )
  })
})
