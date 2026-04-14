import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'

const mockReset = vi.fn()
const mockRouterPush = vi.fn()
const mockDisconnect = vi.fn()
const mockCommandQueueReset = vi.fn()
const mockPoolDbClearAll = vi.fn()
const mockPoolReset = vi.fn()
const mockWorkspaceReset = vi.fn()
const mockStopPersisting = vi.fn()

let mockIsAuthenticated = true

vi.mock('@/stores/auth', () => ({
  useAuthStore: () => ({
    get isAuthenticated() {
      return mockIsAuthenticated
    },
    $reset: mockReset,
  }),
}))

vi.mock('@/composables/usePoolPersistence', () => ({
  usePoolPersistence: () => ({
    stopPersisting: mockStopPersisting,
  }),
}))

vi.mock('@/stores/websocket', () => ({
  useWebSocketStore: () => ({
    disconnect: mockDisconnect,
  }),
}))

vi.mock('@/stores/commandQueue', () => ({
  useCommandQueueStore: () => ({
    reset: mockCommandQueueReset,
  }),
}))

vi.mock('@/api/poolDb', () => ({
  clearAll: mockPoolDbClearAll,
}))

vi.mock('@/stores/objectPool', () => ({
  useObjectPoolStore: () => ({
    $reset: mockPoolReset,
  }),
}))

vi.mock('@/stores/workspace', () => ({
  useWorkspaceStore: () => ({
    $reset: mockWorkspaceReset,
  }),
}))

vi.mock('@/router', () => ({
  default: { push: mockRouterPush },
}))

describe('handleSessionExpired', () => {
  beforeEach(() => {
    vi.resetModules()
    setActivePinia(createPinia())
    mockIsAuthenticated = true
    vi.clearAllMocks()
    localStorage.setItem('test_key', 'test_value')

    // Stub caches API. Includes a workbox precache entry so we can assert it
    // is preserved (clearing it would break offline cold-launch).
    vi.stubGlobal('caches', {
      keys: vi
        .fn()
        .mockResolvedValue([
          'api-auth',
          'workbox-precache-v2-https://tayaway.nl/',
        ]),
      delete: vi.fn().mockResolvedValue(true),
    })
  })

  afterEach(() => {
    vi.unstubAllGlobals()
    localStorage.clear()
  })

  async function callHandler() {
    const mod = await import('./sessionExpired')
    await mod.handleSessionExpired()
  }

  it('resets the auth store', async () => {
    await callHandler()
    expect(mockReset).toHaveBeenCalledOnce()
  })

  it('stops pool persistence', async () => {
    await callHandler()
    expect(mockStopPersisting).toHaveBeenCalledOnce()
  })

  it('disconnects WebSocket', async () => {
    await callHandler()
    expect(mockDisconnect).toHaveBeenCalledOnce()
  })

  it('resets the command queue', async () => {
    await callHandler()
    expect(mockCommandQueueReset).toHaveBeenCalledOnce()
  })

  it('clears IndexedDB pool cache', async () => {
    await callHandler()
    expect(mockPoolDbClearAll).toHaveBeenCalledOnce()
  })

  it('resets Pinia stores', async () => {
    await callHandler()
    expect(mockPoolReset).toHaveBeenCalledOnce()
    expect(mockWorkspaceReset).toHaveBeenCalledOnce()
  })

  it('clears all localStorage', async () => {
    await callHandler()
    expect(localStorage.getItem('test_key')).toBeNull()
  })

  it('clears user-data caches but preserves the workbox precache', async () => {
    await callHandler()
    expect(caches.keys).toHaveBeenCalledOnce()
    expect(caches.delete).toHaveBeenCalledWith('api-auth')
    expect(caches.delete).not.toHaveBeenCalledWith(
      'workbox-precache-v2-https://tayaway.nl/'
    )
  })

  it('redirects to login with session_revoked reason', async () => {
    await callHandler()
    expect(mockRouterPush).toHaveBeenCalledWith({
      name: 'login',
      query: { reason: 'session_revoked' },
    })
  })

  it('does nothing when already logged out', async () => {
    mockIsAuthenticated = false
    await callHandler()
    expect(mockDisconnect).not.toHaveBeenCalled()
    expect(mockRouterPush).not.toHaveBeenCalled()
  })

  it('prevents concurrent calls', async () => {
    // Make router.push block so the first call stays in "handling" state
    let resolveRouter!: () => void
    mockRouterPush.mockImplementationOnce(
      () =>
        new Promise<void>((r) => {
          resolveRouter = r
        })
    )

    const mod = await import('./sessionExpired')
    const first = mod.handleSessionExpired()

    // Yield so the first call progresses past $reset up to the blocked router.push
    await new Promise((r) => setTimeout(r, 0))
    expect(mockReset).toHaveBeenCalledTimes(1)

    // Second call while first is in progress — should be a no-op
    await mod.handleSessionExpired()
    expect(mockReset).toHaveBeenCalledTimes(1) // still 1, not 2

    resolveRouter()
    await first
  })

  it('resets handling flag after completion', async () => {
    const mod = await import('./sessionExpired')
    await mod.handleSessionExpired()

    // Reset mocks and re-authenticate for second call
    vi.clearAllMocks()
    mockIsAuthenticated = true

    await mod.handleSessionExpired()
    expect(mockReset).toHaveBeenCalledOnce()
  })

  it('tolerates caches API being unavailable', async () => {
    vi.stubGlobal('caches', {
      keys: vi.fn().mockRejectedValue(new Error('not available')),
      delete: vi.fn(),
    })

    await expect(callHandler()).resolves.not.toThrow()
    expect(mockRouterPush).toHaveBeenCalled()
  })
})
