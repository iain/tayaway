import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { usePoolPersistence } from './usePoolPersistence'
import * as poolDb from '@/api/poolDb'
import { onPoolChange } from '@/stores/objectPool'

vi.mock('@/api/poolDb', () => ({
  CACHE_VERSION: 4,
  saveObjects: vi.fn().mockResolvedValue(undefined),
  removeObjects: vi.fn().mockResolvedValue(undefined),
  savePendingUpdates: vi.fn().mockResolvedValue(undefined),
  replaceAll: vi.fn().mockResolvedValue(undefined),
  saveSyncedAt: vi.fn().mockResolvedValue(undefined),
  loadAll: vi.fn().mockResolvedValue({
    workspaceId: null,
    syncedAt: null,
    cacheVersion: 4,
    objects: [],
    pendingUpdates: new Map(),
  }),
  clearAll: vi.fn().mockResolvedValue(undefined),
}))

vi.mock('@/stores/objectPool', () => ({
  useObjectPoolStore: vi.fn(() => ({ pendingUpdates: new Map() })),
  onPoolChange: vi.fn(),
  offPoolChange: vi.fn(),
}))

vi.mock('@/stores/websocket', () => ({
  useWebSocketStore: vi.fn(() => ({
    hasSynced: false,
    hasCachedData: false,
    setCacheStaleLevel: vi.fn(),
    restoreSyncTimestamp: vi.fn(),
    getSyncedAt: vi.fn(() => null),
  })),
}))

vi.mock('@/stores/workspace', () => ({
  useWorkspaceStore: vi.fn(() => ({
    currentWorkspaceId: 'ws-1',
  })),
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

describe('usePoolPersistence — visibilitychange flush', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.useFakeTimers()
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
    usePoolPersistence().stopPersisting()
    vi.useRealTimers()
    Object.defineProperty(document, 'visibilityState', {
      value: 'visible',
      configurable: true,
    })
  })

  it('registers a visibilitychange listener on startPersisting', () => {
    const addSpy = vi.spyOn(document, 'addEventListener')
    const { startPersisting } = usePoolPersistence()
    startPersisting()
    expect(addSpy).toHaveBeenCalledWith(
      'visibilitychange',
      expect.any(Function)
    )
    addSpy.mockRestore()
  })

  it('removes the visibilitychange listener on stopPersisting', () => {
    const { startPersisting, stopPersisting } = usePoolPersistence()
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
    let capturedPoolChangeHandler: ((change: unknown) => void) | null = null
    vi.mocked(onPoolChange).mockImplementation((handler) => {
      capturedPoolChangeHandler = handler
    })

    const { startPersisting } = usePoolPersistence()
    startPersisting()

    expect(capturedPoolChangeHandler).not.toBeNull()

    // Simulate a pool 'set' change — this schedules a 500ms debounce
    capturedPoolChangeHandler!({
      type: 'set',
      object: {
        id: 'evt-1',
        objectType: 'event',
        updatedAt: '2026-01-01T00:00:00.000Z',
      },
    })

    // The debounce timer is now active — saveObjects has NOT been called yet
    expect(poolDb.saveObjects).not.toHaveBeenCalled()

    // Simulate the page becoming hidden before the 500ms timer fires
    triggerVisibilityChange('hidden')

    // flushWrites is async — let pending microtasks settle
    await Promise.resolve()
    await Promise.resolve()

    expect(poolDb.saveObjects).toHaveBeenCalledTimes(1)
    expect(poolDb.saveObjects).toHaveBeenCalledWith([
      expect.objectContaining({ id: 'evt-1', objectType: 'event' }),
    ])

    // Advancing the full timer should not trigger a second write
    await vi.advanceTimersByTimeAsync(500)
    expect(poolDb.saveObjects).toHaveBeenCalledTimes(1)
  })

  it('does not flush when page becomes visible', async () => {
    let capturedPoolChangeHandler: ((change: unknown) => void) | null = null
    vi.mocked(onPoolChange).mockImplementation((handler) => {
      capturedPoolChangeHandler = handler
    })

    const { startPersisting } = usePoolPersistence()
    startPersisting()

    capturedPoolChangeHandler!({
      type: 'set',
      object: {
        id: 'evt-2',
        objectType: 'event',
        updatedAt: '2026-01-01T00:00:00.000Z',
      },
    })

    // visibilityState remains 'visible' — handler should not flush
    triggerVisibilityChange('visible')

    await Promise.resolve()
    await Promise.resolve()

    // Debounce still pending — no write yet
    expect(poolDb.saveObjects).not.toHaveBeenCalled()
  })
})
