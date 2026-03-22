import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'

const mockStopPersisting = vi.fn()
vi.mock('@/composables/usePoolPersistence', () => ({
  usePoolPersistence: vi.fn(() => ({
    loadFromCache: vi.fn(),
    startPersisting: vi.fn(),
    stopPersisting: mockStopPersisting,
  })),
}))

// Stub out stores that auth.ts imports but are irrelevant to initialize()
vi.mock('./commandQueue', () => ({
  useCommandQueueStore: vi.fn(() => ({
    enqueue: vi.fn(),
    reset: vi.fn(),
    pendingCount: 0,
    processQueue: vi.fn(),
  })),
}))

vi.mock('./objectPool', () => ({
  useObjectPoolStore: vi.fn(() => ({
    importObjects: vi.fn(),
    remove: vi.fn(),
    findBy: vi.fn(),
    get: vi.fn(),
    $reset: vi.fn(),
  })),
}))

vi.mock('./websocket', () => ({
  useWebSocketStore: vi.fn(() => ({
    connect: vi.fn(),
    disconnect: vi.fn(),
  })),
}))

vi.mock('./workspace', () => ({
  useWorkspaceStore: vi.fn(() => ({
    $reset: vi.fn(),
  })),
}))

vi.mock('@/api/poolDb', () => ({
  clearAll: vi.fn(),
}))

vi.mock('@/composables/useMutation', () => ({
  useMutation: vi.fn(() => ({
    mutate: vi.fn(),
    update: vi.fn(),
  })),
}))

// Cache key and TTL must match the constants in auth.ts
const AUTH_USER_KEY = 'tayaway_auth_user'
const AUTH_USER_TTL_MS = 24 * 60 * 60 * 1000 // 24 hours

const CACHED_USER = {
  id: 'user-1',
  email: 'user@example.com',
  name: 'Test User',
  phoneNumber: null,
  birthday: null,
  locationName: null,
  latitude: null,
  longitude: null,
  iban: null,
}

/** Writes a valid new-format cache entry (with cachedAt timestamp). */
function seedCache(cachedAt = Date.now()) {
  localStorage.setItem(
    AUTH_USER_KEY,
    JSON.stringify({ user: { ...CACHED_USER, iban: null }, cachedAt })
  )
}

/** Writes the old flat-user format (no cachedAt), simulating a pre-TTL client. */
function seedLegacyCache() {
  localStorage.setItem(AUTH_USER_KEY, JSON.stringify(CACHED_USER))
}

describe('auth store – initialize() error handling', () => {
  let consoleSpy: ReturnType<typeof vi.spyOn>

  beforeEach(() => {
    vi.resetModules()
    setActivePinia(createPinia())
    consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {})
    vi.stubGlobal('fetch', vi.fn())
    localStorage.clear()
  })

  afterEach(() => {
    consoleSpy.mockRestore()
    vi.unstubAllGlobals()
  })

  it('falls back to cached user silently on a TypeError (network error)', async () => {
    seedCache()
    vi.mocked(fetch).mockRejectedValue(new TypeError('Failed to fetch'))

    const { useAuthStore } = await import('./auth')
    const store = useAuthStore()
    await store.initialize()

    expect(store.user).toMatchObject({ id: 'user-1' })
    expect(consoleSpy).not.toHaveBeenCalled()
  })

  it('falls back to cached user silently on an AbortError (timeout)', async () => {
    seedCache()
    const abortError = new DOMException(
      'The operation was aborted.',
      'AbortError'
    )
    vi.mocked(fetch).mockRejectedValue(abortError)

    const { useAuthStore } = await import('./auth')
    const store = useAuthStore()
    await store.initialize()

    expect(store.user).toMatchObject({ id: 'user-1' })
    expect(consoleSpy).not.toHaveBeenCalled()
  })

  it('falls back to cached user AND logs on an unexpected error (programming bug)', async () => {
    seedCache()
    const bug = new ReferenceError('someUndefinedVariable is not defined')
    vi.mocked(fetch).mockRejectedValue(bug)

    const { useAuthStore } = await import('./auth')
    const store = useAuthStore()
    await store.initialize()

    expect(store.user).toMatchObject({ id: 'user-1' })
    expect(consoleSpy).toHaveBeenCalledWith(
      '[auth] initialize() caught unexpected error:',
      bug
    )
  })

  it('logs a TypeError that does not match the network error pattern (programming bug, not network)', async () => {
    // A TypeError from a programming mistake (e.g. accessing .json() on undefined)
    // should be logged — only TypeErrors whose message matches the network pattern
    // are treated as genuine network failures and swallowed silently.
    seedCache()
    const bug = new TypeError(
      'Cannot read properties of undefined (reading "json")'
    )
    vi.mocked(fetch).mockRejectedValue(bug)

    const { useAuthStore } = await import('./auth')
    const store = useAuthStore()
    await store.initialize()

    expect(store.user).toMatchObject({ id: 'user-1' })
    expect(consoleSpy).toHaveBeenCalledWith(
      '[auth] initialize() caught unexpected error:',
      bug
    )
  })

  it('falls back to null and logs when there is no cached user and an unexpected error occurs', async () => {
    // No cache seeded
    const bug = new SyntaxError('Unexpected token')
    vi.mocked(fetch).mockRejectedValue(bug)

    const { useAuthStore } = await import('./auth')
    const store = useAuthStore()
    await store.initialize()

    expect(store.user).toBeNull()
    expect(consoleSpy).toHaveBeenCalledWith(
      '[auth] initialize() caught unexpected error:',
      bug
    )
  })

  it('sets initialized = true even after an unexpected error', async () => {
    vi.mocked(fetch).mockRejectedValue(new Error('boom'))

    const { useAuthStore } = await import('./auth')
    const store = useAuthStore()
    await store.initialize()

    expect(store.initialized).toBe(true)
  })
})

describe('auth store – cached user TTL', () => {
  let consoleSpy: ReturnType<typeof vi.spyOn>

  beforeEach(() => {
    vi.resetModules()
    setActivePinia(createPinia())
    consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {})
    vi.stubGlobal('fetch', vi.fn())
    localStorage.clear()
  })

  afterEach(() => {
    consoleSpy.mockRestore()
    vi.unstubAllGlobals()
  })

  it('uses a fresh cached user (within TTL) when the server is unreachable', async () => {
    seedCache(Date.now() - 60 * 60 * 1000) // 1 hour ago — well within 24h TTL
    vi.mocked(fetch).mockRejectedValue(new TypeError('Failed to fetch'))

    const { useAuthStore } = await import('./auth')
    const store = useAuthStore()
    await store.initialize()

    expect(store.user).toMatchObject({ id: 'user-1' })
  })

  it('treats an expired cached user (beyond TTL) as unauthenticated when the server is unreachable', async () => {
    seedCache(Date.now() - AUTH_USER_TTL_MS - 1000) // just over 24h ago
    vi.mocked(fetch).mockRejectedValue(new TypeError('Failed to fetch'))

    const { useAuthStore } = await import('./auth')
    const store = useAuthStore()
    await store.initialize()

    expect(store.user).toBeNull()
    expect(localStorage.getItem(AUTH_USER_KEY)).toBeNull()
  })

  it('clears a legacy cache entry (no cachedAt) and treats user as unauthenticated when the server is unreachable', async () => {
    seedLegacyCache()
    vi.mocked(fetch).mockRejectedValue(new TypeError('Failed to fetch'))

    const { useAuthStore } = await import('./auth')
    const store = useAuthStore()
    await store.initialize()

    expect(store.user).toBeNull()
    expect(localStorage.getItem(AUTH_USER_KEY)).toBeNull()
  })

  it('refreshes the cached timestamp on a successful /me response', async () => {
    const before = Date.now()
    vi.mocked(fetch).mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({
        user_id: 'user-1',
        email: 'user@example.com',
        name: 'Test User',
        phoneNumber: null,
        birthday: null,
        locationName: null,
        latitude: null,
        longitude: null,
        iban: null,
      }),
    } as Response)

    const { useAuthStore } = await import('./auth')
    const store = useAuthStore()
    await store.initialize()

    const raw = localStorage.getItem(AUTH_USER_KEY)
    expect(raw).not.toBeNull()
    const entry = JSON.parse(raw!) as { cachedAt: number }
    expect(entry.cachedAt).toBeGreaterThanOrEqual(before)
  })
})

describe('auth store – logout()', () => {
  beforeEach(() => {
    vi.resetModules()
    setActivePinia(createPinia())
    vi.stubGlobal('fetch', vi.fn())
    localStorage.clear()
    mockStopPersisting.mockClear()
  })

  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('calls stopPersisting() during logout', async () => {
    vi.mocked(fetch).mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({}),
    } as Response)

    const { useAuthStore } = await import('./auth')
    const store = useAuthStore()
    await store.logout()

    expect(mockStopPersisting).toHaveBeenCalledOnce()
  })

  it('calls stopPersisting() even when the logout API call fails', async () => {
    vi.mocked(fetch).mockRejectedValue(new TypeError('Failed to fetch'))

    const { useAuthStore } = await import('./auth')
    const store = useAuthStore()
    await store.logout().catch(() => {})

    expect(mockStopPersisting).toHaveBeenCalledOnce()
  })
})
