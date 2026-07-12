import { Scope } from '@/api/scope'
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { poolPersistence } from './poolPersistence'
import * as poolDb from '@/api/poolDb'
import {
  onPoolChange,
  useObjectPoolStore,
  type PoolChange,
} from '@/stores/objectPool'
import { useWebSocketStore } from '@/stores/websocket'
import type { PoolObject } from '@/types/pool'

// Minimal requestIdleCallback polyfill for JSDOM (which does not implement it).
// Must be installed after vi.useFakeTimers() since fake timers may clobber globals.
// The callbacks map is re-created each beforeEach to ensure clean state.
let idleCallbacks: Map<number, IdleRequestCallback> = new Map()
let idleHandle = 0

function installIdlePolyfill(): void {
  idleHandle = 0
  idleCallbacks = new Map()
  globalThis.requestIdleCallback = (cb: IdleRequestCallback): number => {
    const handle = ++idleHandle
    idleCallbacks.set(handle, cb)
    return handle
  }
  globalThis.cancelIdleCallback = (handle: number): void => {
    idleCallbacks.delete(handle)
  }
}

function flushIdleCallbacks(): void {
  for (const [handle, cb] of idleCallbacks) {
    idleCallbacks.delete(handle)
    cb({ didTimeout: false, timeRemaining: () => 50 } as IdleDeadline)
  }
}

vi.mock('@/api/poolDb', () => ({
  CACHE_VERSION: 11,
  saveObjects: vi.fn().mockResolvedValue(undefined),
  removeObjects: vi.fn().mockResolvedValue(undefined),
  savePendingUpdates: vi.fn().mockResolvedValue(undefined),
  replaceScope: vi.fn().mockResolvedValue(undefined),
  clearScope: vi.fn().mockResolvedValue(undefined),
  saveSyncedAt: vi.fn().mockResolvedValue(undefined),
  loadMeta: vi.fn().mockResolvedValue({
    cacheVersion: 11,
    syncedAt: new Map(),
    fullSyncedAt: new Map(),
  }),
  loadObjectsByType: vi.fn().mockResolvedValue([]),
  loadPendingUpdatesFromDb: vi.fn().mockResolvedValue(new Map()),
  clearAll: vi.fn().mockResolvedValue(undefined),
}))

vi.mock('@/stores/objectPool', () => ({
  useObjectPoolStore: vi.fn(() => ({
    pendingUpdates: new Map(),
    importObjects: vi.fn(),
    restorePendingUpdates: vi.fn(),
    getServer: vi.fn(() => undefined),
  })),
  onPoolChange: vi.fn(),
  offPoolChange: vi.fn(),
}))

vi.mock('@/stores/websocket', () => ({
  useWebSocketStore: vi.fn(() => ({
    hasSynced: false,
    hasCachedData: false,
    restoreSyncTimestamp: vi.fn(),
    getSyncedAt: vi.fn(() => null),
    restoreFullSyncTimestamp: vi.fn(),
    getFullSyncedAt: vi.fn(() => null),
  })),
}))

vi.mock('@/stores/workspace', () => ({
  useWorkspaceStore: vi.fn(() => ({
    currentWorkspaceId: 'ws-1',
  })),
  WORKSPACE_ID_STORAGE_KEY: 'current_workspace_id',
}))

vi.mock('@/stores/auth', () => ({
  useAuthStore: vi.fn(() => ({ currentUserId: 'user-1' })),
}))

// Dispatch a real visibilitychange event after setting visibilityState so the
// handler can read document.visibilityState correctly
function triggerVisibilityChange(state: 'hidden' | 'visible'): void {
  Object.defineProperty(document, 'visibilityState', {
    value: state,
    configurable: true,
  })
  document.dispatchEvent(new Event('visibilitychange'))
}

describe('poolPersistence — visibilitychange flush', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.useFakeTimers()
    // Install the polyfill after useFakeTimers() so it isn't overridden
    installIdlePolyfill()
    vi.mocked(poolDb.saveObjects).mockReset().mockResolvedValue(undefined)
    vi.mocked(poolDb.removeObjects).mockReset().mockResolvedValue(undefined)
    vi.mocked(onPoolChange).mockReset()

    Object.defineProperty(document, 'visibilityState', {
      value: 'visible',
      configurable: true,
    })
  })

  afterEach(() => {
    // Reset module-level state so subsequent tests start clean
    poolPersistence.stopPersisting()
    vi.useRealTimers()
    Object.defineProperty(document, 'visibilityState', {
      value: 'visible',
      configurable: true,
    })
  })

  it('registers a visibilitychange listener on startPersisting', () => {
    const addSpy = vi.spyOn(document, 'addEventListener')
    const { startPersisting } = poolPersistence
    startPersisting()
    expect(addSpy).toHaveBeenCalledWith(
      'visibilitychange',
      expect.any(Function)
    )
    addSpy.mockRestore()
  })

  it('removes the visibilitychange listener on stopPersisting', () => {
    const { startPersisting, stopPersisting } = poolPersistence
    startPersisting()
    const removeSpy = vi.spyOn(document, 'removeEventListener')
    stopPersisting()
    expect(removeSpy).toHaveBeenCalledWith(
      'visibilitychange',
      expect.any(Function)
    )
    removeSpy.mockRestore()
  })

  it('flushes pending saves immediately when page becomes hidden', async () => {
    // Capture the pool change handler so we can simulate incoming pool changes
    let capturedPoolChangeHandler: ((change: PoolChange) => void) | null = null
    vi.mocked(onPoolChange).mockImplementation((handler) => {
      capturedPoolChangeHandler = handler
    })

    const { startPersisting } = poolPersistence
    startPersisting()

    expect(capturedPoolChangeHandler).not.toBeNull()

    // Simulate a pool 'set' change — this schedules a 500ms debounce
    capturedPoolChangeHandler!({
      type: 'set',
      scope: Scope.workspace('ws-1'),
      object: {
        id: 'evt-1',
        objectType: 'event',
        workspaceId: 'ws-1',
        updatedAt: '2026-01-01T00:00:00.000Z',
      } as PoolObject,
    })

    // The debounce timer is now active — saveObjects has NOT been called yet
    expect(poolDb.saveObjects).not.toHaveBeenCalled()

    // Simulate the page becoming hidden before the 500ms timer fires
    triggerVisibilityChange('hidden')

    // flushWrites is async — let pending microtasks settle
    await Promise.resolve()
    await Promise.resolve()

    expect(poolDb.saveObjects).toHaveBeenCalledTimes(1)
    expect(poolDb.saveObjects).toHaveBeenCalledWith(Scope.workspace('ws-1'), [
      expect.objectContaining({ id: 'evt-1', objectType: 'event' }),
    ])

    // Advancing the full timer should not trigger a second write
    await vi.advanceTimersByTimeAsync(500)
    expect(poolDb.saveObjects).toHaveBeenCalledTimes(1)
  })

  it('does not flush when page becomes visible', async () => {
    let capturedPoolChangeHandler: ((change: PoolChange) => void) | null = null
    vi.mocked(onPoolChange).mockImplementation((handler) => {
      capturedPoolChangeHandler = handler
    })

    const { startPersisting } = poolPersistence
    startPersisting()

    capturedPoolChangeHandler!({
      type: 'set',
      scope: Scope.workspace('ws-1'),
      object: {
        id: 'evt-2',
        objectType: 'event',
        workspaceId: 'ws-1',
        updatedAt: '2026-01-01T00:00:00.000Z',
      } as PoolObject,
    })

    // visibilityState remains 'visible' — handler should not flush
    triggerVisibilityChange('visible')

    await Promise.resolve()
    await Promise.resolve()

    // Debounce still pending — no write yet
    expect(poolDb.saveObjects).not.toHaveBeenCalled()
  })

  it('defers writes via requestIdleCallback after the 500ms debounce', async () => {
    let capturedPoolChangeHandler: ((change: PoolChange) => void) | null = null
    vi.mocked(onPoolChange).mockImplementation((handler) => {
      capturedPoolChangeHandler = handler
    })

    const { startPersisting } = poolPersistence
    startPersisting()

    capturedPoolChangeHandler!({
      type: 'set',
      scope: Scope.workspace('ws-1'),
      object: {
        id: 'evt-3',
        objectType: 'event',
        workspaceId: 'ws-1',
        updatedAt: '2026-01-01T00:00:00.000Z',
      } as PoolObject,
    })

    // After the 500ms debounce fires, the write is pending as an idle callback —
    // not yet executed.
    await vi.advanceTimersByTimeAsync(500)
    expect(poolDb.saveObjects).not.toHaveBeenCalled()
    expect(idleCallbacks.size).toBe(1)

    // Once the browser becomes idle, the write executes.
    flushIdleCallbacks()
    await Promise.resolve()
    await Promise.resolve()

    expect(poolDb.saveObjects).toHaveBeenCalledTimes(1)
    expect(poolDb.saveObjects).toHaveBeenCalledWith(Scope.workspace('ws-1'), [
      expect.objectContaining({ id: 'evt-3', objectType: 'event' }),
    ])
  })

  it('flushes immediately when page becomes hidden while idle callback is pending', async () => {
    let capturedPoolChangeHandler: ((change: PoolChange) => void) | null = null
    vi.mocked(onPoolChange).mockImplementation((handler) => {
      capturedPoolChangeHandler = handler
    })

    const { startPersisting } = poolPersistence
    startPersisting()

    capturedPoolChangeHandler!({
      type: 'set',
      scope: Scope.workspace('ws-1'),
      object: {
        id: 'evt-4',
        objectType: 'event',
        workspaceId: 'ws-1',
        updatedAt: '2026-01-01T00:00:00.000Z',
      } as PoolObject,
    })

    // Advance past debounce — idle callback is now registered but not yet run
    await vi.advanceTimersByTimeAsync(500)
    expect(idleCallbacks.size).toBe(1)
    expect(poolDb.saveObjects).not.toHaveBeenCalled()

    // Page becomes hidden — should flush immediately, cancelling the idle callback
    triggerVisibilityChange('hidden')

    await Promise.resolve()
    await Promise.resolve()

    expect(poolDb.saveObjects).toHaveBeenCalledTimes(1)
    // The idle callback should have been cancelled — flushing again should be a no-op
    expect(idleCallbacks.size).toBe(0)
  })

  it('cancels the idle callback on stopPersisting', async () => {
    let capturedPoolChangeHandler: ((change: PoolChange) => void) | null = null
    vi.mocked(onPoolChange).mockImplementation((handler) => {
      capturedPoolChangeHandler = handler
    })

    const { startPersisting, stopPersisting } = poolPersistence
    startPersisting()

    capturedPoolChangeHandler!({
      type: 'set',
      scope: Scope.workspace('ws-1'),
      object: {
        id: 'evt-5',
        objectType: 'event',
        workspaceId: 'ws-1',
        updatedAt: '2026-01-01T00:00:00.000Z',
      } as PoolObject,
    })

    await vi.advanceTimersByTimeAsync(500)
    expect(idleCallbacks.size).toBe(1)

    stopPersisting()

    expect(idleCallbacks.size).toBe(0)
    // No writes should have happened
    expect(poolDb.saveObjects).not.toHaveBeenCalled()
  })
})

describe('poolPersistence — multi-workspace scope routing', () => {
  let capturedHandler: ((change: PoolChange) => void) | null = null

  beforeEach(() => {
    setActivePinia(createPinia())
    vi.useFakeTimers()
    installIdlePolyfill()
    capturedHandler = null
    vi.mocked(onPoolChange)
      .mockReset()
      .mockImplementation((h) => {
        capturedHandler = h
      })
    vi.mocked(poolDb.saveObjects).mockReset().mockResolvedValue(undefined)
    vi.mocked(poolDb.replaceScope).mockReset().mockResolvedValue(undefined)
    vi.mocked(poolDb.clearAll).mockReset().mockResolvedValue(undefined)
    poolPersistence.startPersisting()
  })

  afterEach(() => {
    poolPersistence.stopPersisting()
    vi.useRealTimers()
  })

  it('writes each object to the scope its change event carries', async () => {
    // Events declare their scope explicitly; the persistence layer just
    // routes by that tag and doesn't re-classify anything.
    capturedHandler!({
      type: 'set',
      scope: Scope.personal(),
      object: {
        id: 'note-1',
        objectType: 'notification',
        userId: 'user-1',
        workspaceId: 'ws-2',
        updatedAt: '2026-01-01T00:00:00.000Z',
      } as unknown as PoolObject,
    })
    capturedHandler!({
      type: 'set',
      scope: Scope.workspace('ws-1'),
      object: {
        id: 'evt-A',
        objectType: 'event',
        workspaceId: 'ws-1',
        updatedAt: '2026-01-01T00:00:00.000Z',
      } as PoolObject,
    })

    await vi.advanceTimersByTimeAsync(500)
    flushIdleCallbacks()
    await Promise.resolve()
    await Promise.resolve()

    expect(poolDb.saveObjects).toHaveBeenCalledWith(Scope.personal(), [
      expect.objectContaining({ id: 'note-1' }),
    ])
    expect(poolDb.saveObjects).toHaveBeenCalledWith(Scope.workspace('ws-1'), [
      expect.objectContaining({ id: 'evt-A' }),
    ])
  })

  it('replaces only the active workspace scope on a full sync — other workspaces survive', async () => {
    capturedHandler!({
      type: 'replaceScope',
      scope: Scope.workspace('ws-1'),
      objects: [
        {
          id: 'evt-A',
          objectType: 'event',
          workspaceId: 'ws-1',
          updatedAt: '2026-01-01T00:00:00.000Z',
        } as PoolObject,
      ],
    })

    await Promise.resolve()

    expect(poolDb.replaceScope).toHaveBeenCalledWith(
      Scope.workspace('ws-1'),
      expect.arrayContaining([expect.objectContaining({ id: 'evt-A' })]),
      undefined,
      undefined
    )
    expect(poolDb.clearAll).not.toHaveBeenCalled()
  })
})

describe('poolPersistence — progressive cache loading', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.useFakeTimers()
    installIdlePolyfill()
    localStorage.setItem('current_workspace_id', 'ws-1')

    vi.mocked(poolDb.loadMeta)
      .mockReset()
      .mockResolvedValue({
        cacheVersion: 11,
        syncedAt: new Map([
          [Scope.workspace('ws-1'), new Date().toISOString()],
        ]),
        fullSyncedAt: new Map(),
      })
    vi.mocked(poolDb.loadObjectsByType).mockReset().mockResolvedValue([])
    vi.mocked(poolDb.loadPendingUpdatesFromDb)
      .mockReset()
      .mockResolvedValue(new Map())
    vi.mocked(poolDb.clearAll).mockReset().mockResolvedValue(undefined)

    vi.mocked(useObjectPoolStore).mockReturnValue({
      pendingUpdates: new Map(),
      importObjects: vi.fn(),
      restorePendingUpdates: vi.fn(),
    } as unknown as ReturnType<typeof useObjectPoolStore>)

    vi.mocked(useWebSocketStore).mockReturnValue({
      hasSynced: false,
      hasCachedData: false,
      restoreSyncTimestamp: vi.fn(),
      getSyncedAt: vi.fn(() => null),
      restoreFullSyncTimestamp: vi.fn(),
      getFullSyncedAt: vi.fn(() => null),
    } as unknown as ReturnType<typeof useWebSocketStore>)
  })

  afterEach(() => {
    localStorage.removeItem('current_workspace_id')
    poolPersistence.stopPersisting()
    vi.useRealTimers()
  })

  it('reads metadata first then loads objects by type', async () => {
    const memberObj = {
      id: 'm-1',
      objectType: 'member',
      updatedAt: '2026-01-01T00:00:00.000Z',
    } as PoolObject
    const eventObj = {
      id: 'e-1',
      objectType: 'event',
      updatedAt: '2026-01-01T00:00:00.000Z',
    } as PoolObject

    vi.mocked(poolDb.loadObjectsByType).mockImplementation(
      async (scope, type) => {
        if (scope === Scope.workspace('ws-1') && type === 'member')
          return [memberObj]
        if (scope === Scope.workspace('ws-1') && type === 'event')
          return [eventObj]
        return []
      }
    )

    const pool = useObjectPoolStore()
    const { loadFromCache } = poolPersistence

    // Run all timers and microtasks to complete progressive loading
    const loadPromise = loadFromCache()
    await vi.runAllTimersAsync()
    await loadPromise

    expect(poolDb.loadMeta).toHaveBeenCalledTimes(1)
    expect(poolDb.loadObjectsByType).toHaveBeenCalledWith(
      Scope.personal(),
      'member'
    )
    expect(poolDb.loadObjectsByType).toHaveBeenCalledWith(
      Scope.workspace('ws-1'),
      'member'
    )
    expect(poolDb.loadObjectsByType).toHaveBeenCalledWith(
      Scope.workspace('ws-1'),
      'event'
    )
    expect(pool.importObjects).toHaveBeenCalledWith([memberObj], {
      scope: Scope.workspace('ws-1'),
    })
    expect(pool.importObjects).toHaveBeenCalledWith([eventObj], {
      scope: Scope.workspace('ws-1'),
    })
  })

  it('clears the workspace scope and returns when its cache is too stale', async () => {
    const oldDate = new Date(
      Date.now() - 1000 * 60 * 60 * 24 * 30
    ).toISOString()
    vi.mocked(poolDb.loadMeta).mockResolvedValue({
      cacheVersion: 11,
      syncedAt: new Map([[Scope.workspace('ws-1'), oldDate]]),
      fullSyncedAt: new Map(),
    })

    const pool = useObjectPoolStore()
    const { loadFromCache } = poolPersistence
    await loadFromCache()

    expect(poolDb.clearScope).toHaveBeenCalledWith(Scope.workspace('ws-1'))
    expect(pool.importObjects).not.toHaveBeenCalled()
    expect(poolDb.loadObjectsByType).not.toHaveBeenCalled()
  })

  it('clears cache and returns when cacheVersion is stale', async () => {
    vi.mocked(poolDb.loadMeta).mockResolvedValue({
      cacheVersion: 1, // old version
      syncedAt: new Map(),
      fullSyncedAt: new Map(),
    })

    const pool = useObjectPoolStore()
    const { loadFromCache } = poolPersistence
    await loadFromCache()

    expect(poolDb.clearAll).toHaveBeenCalledTimes(1)
    expect(pool.importObjects).not.toHaveBeenCalled()
  })

  it('stops loading deferred types when server syncs mid-load', async () => {
    const wsStore = useWebSocketStore()

    let memberCallCount = 0
    vi.mocked(poolDb.loadObjectsByType).mockImplementation(
      async (_scope, type) => {
        if (type === 'member') {
          memberCallCount++
          // Simulate server sync arriving while loading members
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          ;(wsStore as any).hasSynced = true
          return []
        }
        return []
      }
    )

    const pool = useObjectPoolStore()
    const { loadFromCache } = poolPersistence
    const loadPromise = loadFromCache()
    await vi.runAllTimersAsync()
    await loadPromise

    // hasSynced is checked at the top of each *type* iteration, not between
    // scopes within a type — so both scope loads for 'member' run (personal
    // and workspace), then the next type ('workspace') sees hasSynced=true
    // and returns. The 'event' bucket is never touched.
    expect(memberCallCount).toBe(2)
    expect(poolDb.loadObjectsByType).toHaveBeenCalledWith(
      Scope.personal(),
      'member'
    )
    expect(poolDb.loadObjectsByType).toHaveBeenCalledWith(
      Scope.workspace('ws-1'),
      'member'
    )
    expect(poolDb.loadObjectsByType).not.toHaveBeenCalledWith(
      expect.anything(),
      'event'
    )
    expect(pool.importObjects).not.toHaveBeenCalled()
  })

  it('loads pending updates after all objects are loaded', async () => {
    const pendingMap = new Map([
      [
        'event:e-1',
        [
          {
            id: 'p-1',
            objectType: 'event',
            objectId: 'e-1',
            changes: { name: 'New' },
            timestamp: Date.now(),
          },
        ],
      ],
    ])
    vi.mocked(poolDb.loadPendingUpdatesFromDb).mockResolvedValue(
      pendingMap as unknown as Awaited<
        ReturnType<typeof poolDb.loadPendingUpdatesFromDb>
      >
    )
    vi.mocked(poolDb.loadObjectsByType).mockImplementation(
      async (scope, type) => {
        if (scope === Scope.workspace('ws-1') && type === 'member') {
          return [
            {
              id: 'm-1',
              objectType: 'member',
              updatedAt: '2026-01-01T00:00:00.000Z',
            } as PoolObject,
          ]
        }
        return []
      }
    )

    const pool = useObjectPoolStore()
    const { loadFromCache } = poolPersistence
    const loadPromise = loadFromCache()
    await vi.runAllTimersAsync()
    await loadPromise

    expect(poolDb.loadPendingUpdatesFromDb).toHaveBeenCalledTimes(1)
    expect(pool.restorePendingUpdates).toHaveBeenCalledWith(pendingMap)
  })

  // Pending overlays represent commands still in the queue — the replay's
  // rollback needs their ids restored, and the user needs to see their
  // offline changes, no matter how the object cache races the first sync.
  it('restores pending updates even when the server synced first', async () => {
    const wsStore = useWebSocketStore()
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    ;(wsStore as any).hasSynced = true
    const pendingMap = new Map([['event:e-1', []]])
    vi.mocked(poolDb.loadPendingUpdatesFromDb).mockResolvedValue(
      pendingMap as unknown as Awaited<
        ReturnType<typeof poolDb.loadPendingUpdatesFromDb>
      >
    )

    const pool = useObjectPoolStore()
    const { loadFromCache } = poolPersistence
    await loadFromCache()

    // Object loading is skipped (server data is authoritative), but the
    // overlays are restored regardless
    expect(poolDb.loadObjectsByType).not.toHaveBeenCalled()
    expect(pool.restorePendingUpdates).toHaveBeenCalledWith(pendingMap)
  })

  // The reconnect cursor is only trusted when the last full sync is known —
  // without restoring it, every cold start degrades to a full sync.
  it('restores the full-sync timestamp alongside the cursor', async () => {
    const syncedAt = new Date().toISOString()
    const fullSyncedAt = new Date(Date.now() - 60_000).toISOString()
    vi.mocked(poolDb.loadMeta).mockResolvedValue({
      cacheVersion: 11,
      syncedAt: new Map([[Scope.workspace('ws-1'), syncedAt]]),
      fullSyncedAt: new Map([[Scope.workspace('ws-1'), fullSyncedAt]]),
    })
    vi.mocked(poolDb.loadObjectsByType).mockResolvedValue([
      {
        id: 'm-1',
        objectType: 'member',
        updatedAt: '2026-01-01T00:00:00.000Z',
      } as PoolObject,
    ])

    const wsStore = useWebSocketStore()
    const { loadFromCache } = poolPersistence
    const loadPromise = loadFromCache()
    await vi.runAllTimersAsync()
    await loadPromise

    expect(wsStore.restoreSyncTimestamp).toHaveBeenCalledWith('ws-1', syncedAt)
    expect(wsStore.restoreFullSyncTimestamp).toHaveBeenCalledWith(
      'ws-1',
      fullSyncedAt
    )
  })
})
