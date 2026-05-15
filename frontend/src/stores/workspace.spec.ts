import { describe, it, expect, vi, beforeEach } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useWorkspaceStore } from './workspace'
import { useObjectPoolStore } from './objectPool'
import * as poolDb from '@/api/poolDb'
import type { PoolObject } from '@/types/pool'

vi.mock('@/api/poolDb', () => ({
  PERSONAL_SCOPE: 'personal',
  workspaceScope: (id: string) => `workspace:${id}`,
  setCurrentWorkspaceId: vi.fn().mockResolvedValue(undefined),
  loadObjectsByType: vi.fn().mockResolvedValue([]),
}))

vi.mock('@/stores/auth', () => ({
  useAuthStore: () => ({ currentUserId: 'user-1' }),
}))

describe('workspace store — switchWorkspace', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    localStorage.clear()
    vi.mocked(poolDb.loadObjectsByType).mockReset().mockResolvedValue([])
    vi.mocked(poolDb.setCurrentWorkspaceId).mockReset().mockResolvedValue(undefined)
  })

  it('hydrates the new workspace cache into the pool so a switch-back shows data before the partial sync', async () => {
    const cached: PoolObject = {
      id: 'evt-cached',
      objectType: 'event',
      workspaceId: 'ws-2',
      name: 'Cached Event',
      eventDate: null,
      datePollId: null,
      createdAt: '2026-01-01T00:00:00.000Z',
      updatedAt: '2026-01-01T00:00:00.000Z',
    } as unknown as PoolObject

    vi.mocked(poolDb.loadObjectsByType).mockImplementation(async (scope, type) => {
      if (scope === 'workspace:ws-2' && type === 'event') return [cached]
      return []
    })

    const store = useWorkspaceStore()
    store.initialize(['ws-1', 'ws-2'])
    expect(store.currentWorkspaceId).toBe('ws-1')

    store.switchWorkspace('ws-2')
    // The hydration is asynchronous — wait for it to resolve.
    await vi.waitFor(() => {
      const pool = useObjectPoolStore()
      expect(pool.get('event', 'evt-cached')).toBeDefined()
    })
  })

  it('persists the new workspace id in IndexedDB on switch', () => {
    const store = useWorkspaceStore()
    store.initialize(['ws-1', 'ws-2'])
    store.switchWorkspace('ws-2')
    expect(poolDb.setCurrentWorkspaceId).toHaveBeenCalledWith('ws-2')
  })
})

describe('workspace store — removed from current workspace', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    localStorage.clear()
    vi.mocked(poolDb.loadObjectsByType).mockReset().mockResolvedValue([])
    vi.mocked(poolDb.setCurrentWorkspaceId).mockReset().mockResolvedValue(undefined)
  })

  it('redirects to the next remaining workspace when the current one disappears from the personal pool', async () => {
    const pool = useObjectPoolStore()
    const wsA: PoolObject = {
      id: 'ws-A',
      objectType: 'workspace',
      name: 'A',
      memberIds: [],
      createdAt: '2026-01-01T00:00:00.000Z',
      updatedAt: '2026-01-01T00:00:00.000Z',
    } as unknown as PoolObject
    const wsB: PoolObject = {
      id: 'ws-B',
      objectType: 'workspace',
      name: 'B',
      memberIds: [],
      createdAt: '2026-01-01T00:00:00.000Z',
      updatedAt: '2026-01-01T00:00:00.000Z',
    } as unknown as PoolObject
    pool.importObjects([wsA, wsB])

    const store = useWorkspaceStore()
    store.initialize(['ws-A', 'ws-B'])
    store.switchWorkspace('ws-A')
    expect(store.currentWorkspaceId).toBe('ws-A')

    // Personal channel: user was removed from ws-A — pool drops the row
    pool.remove('workspace', 'ws-A')

    await vi.waitFor(() => {
      expect(store.currentWorkspaceId).toBe('ws-B')
    })
  })

  it('clears the current workspace and storage when the last workspace disappears', async () => {
    const pool = useObjectPoolStore()
    const ws: PoolObject = {
      id: 'ws-only',
      objectType: 'workspace',
      name: 'Only',
      memberIds: [],
      createdAt: '2026-01-01T00:00:00.000Z',
      updatedAt: '2026-01-01T00:00:00.000Z',
    } as unknown as PoolObject
    pool.importObjects([ws])

    const store = useWorkspaceStore()
    store.initialize(['ws-only'])
    store.switchWorkspace('ws-only')

    pool.remove('workspace', 'ws-only')

    await vi.waitFor(() => {
      expect(store.currentWorkspaceId).toBeNull()
    })
    expect(localStorage.getItem('current_workspace_id')).toBeNull()
  })
})
