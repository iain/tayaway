import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'

// Mock all dynamic imports used inside the websocket store.
// The store uses relative imports (e.g. './auth') which resolve to the same
// module paths as the @/ alias — vitest intercepts both forms.
vi.mock('@/stores/auth', () => ({
  useAuthStore: () => ({
    isAuthenticated: true,
    $reset: vi.fn(),
  }),
}))

vi.mock('@/stores/workspace', () => ({
  useWorkspaceStore: () => ({
    currentWorkspaceId: null,
    initialize: vi.fn(),
  }),
  WORKSPACE_ID_STORAGE_KEY: 'current_workspace_id',
}))

vi.mock('@/stores/objectPool', () => ({
  useObjectPoolStore: () => ({
    importObjects: vi.fn(),
    replaceObjects: vi.fn(),
    cascadeRemove: vi.fn(),
  }),
}))

vi.mock('@/stores/commandQueue', () => ({
  useCommandQueueStore: () => ({
    processQueue: vi.fn(),
  }),
}))

vi.mock('@/router', () => ({
  default: { push: vi.fn() },
}))

vi.mock('@/api/sessionExpired', () => ({
  handleSessionExpired: vi.fn(),
}))

// Mock the @/stores barrel used by the api client
vi.mock('@/stores', () => ({
  useObjectPoolStore: () => ({
    importObjects: vi.fn(),
    remove: vi.fn(),
  }),
  useNotificationsStore: () => ({
    showError: vi.fn(),
  }),
}))

// Track the most recently constructed WebSocket instance so tests can
// trigger handlers directly without a real network connection.
let lastSocket: InstanceType<typeof MockWebSocket>

class MockWebSocket {
  static OPEN = 1
  static CLOSING = 2
  static CLOSED = 3
  static CONNECTING = 0
  readyState = MockWebSocket.OPEN
  onopen: (() => void) | null = null
  onclose: ((event: CloseEvent) => void) | null = null
  onerror: ((event: Event) => void) | null = null
  onmessage: ((event: MessageEvent) => void) | null = null
  close = vi.fn()
  send = vi.fn()

  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  constructor(_url: string) {
    // eslint-disable-next-line @typescript-eslint/no-this-alias
    lastSocket = this
  }
}

vi.stubGlobal('WebSocket', MockWebSocket)

// Import the store after all mocks are registered
const { useWebSocketStore } = await import('@/stores/websocket')

// Return a minimal successful ticket fetch response
function mockSuccessfulTicketFetch(ticket = 'secret-jwt'): void {
  vi.spyOn(globalThis, 'fetch').mockResolvedValue(
    new Response(JSON.stringify({ ticket }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })
  )
}

describe('WebSocket store — connection logging', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.spyOn(console, 'info').mockImplementation(() => {})
    vi.spyOn(console, 'warn').mockImplementation(() => {})
    vi.spyOn(console, 'error').mockImplementation(() => {})
    // Reset socket tracker
    lastSocket = undefined as unknown as InstanceType<typeof MockWebSocket>
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  describe('onopen', () => {
    it('logs the connected URL with the ticket redacted', async () => {
      mockSuccessfulTicketFetch('secret-jwt')

      const store = useWebSocketStore()
      await store.connect()

      expect(lastSocket).toBeDefined()
      lastSocket.onopen?.()

      expect(console.info).toHaveBeenCalledWith(
        '[WebSocket] Connected to',
        expect.stringContaining('ticket=<redacted>')
      )
      expect(console.info).toHaveBeenCalledWith(
        '[WebSocket] Connected to',
        expect.not.stringContaining('secret-jwt')
      )
    })

    it('does not log the raw JWT ticket in the URL', async () => {
      mockSuccessfulTicketFetch('my-very-secret-token')

      const store = useWebSocketStore()
      await store.connect()
      lastSocket.onopen?.()

      const calls = vi.mocked(console.info).mock.calls.flat().join(' ')
      expect(calls).not.toContain('my-very-secret-token')
    })
  })

  describe('onclose', () => {
    it('logs the close code, reason, and reconnect attempt number', async () => {
      mockSuccessfulTicketFetch()

      const store = useWebSocketStore()
      await store.connect()

      expect(lastSocket).toBeDefined()
      lastSocket.onclose?.(
        new CloseEvent('close', { code: 1006, reason: 'Abnormal Closure' })
      )

      expect(console.warn).toHaveBeenCalledWith(
        expect.stringContaining('code: 1006')
      )
      expect(console.warn).toHaveBeenCalledWith(
        expect.stringContaining('Abnormal Closure')
      )
      expect(console.warn).toHaveBeenCalledWith(
        expect.stringContaining('reconnect attempt')
      )
    })

    it('shows "(none)" when no close reason is provided', async () => {
      mockSuccessfulTicketFetch()

      const store = useWebSocketStore()
      await store.connect()

      expect(lastSocket).toBeDefined()
      lastSocket.onclose?.(new CloseEvent('close', { code: 1001, reason: '' }))

      expect(console.warn).toHaveBeenCalledWith(
        expect.stringContaining('(none)')
      )
    })
  })

  describe('onerror', () => {
    it('logs the error event', async () => {
      mockSuccessfulTicketFetch()

      const store = useWebSocketStore()
      await store.connect()

      expect(lastSocket).toBeDefined()
      const fakeEvent = new Event('error')
      lastSocket.onerror?.(fakeEvent)

      expect(console.warn).toHaveBeenCalledWith('[WebSocket] Error', fakeEvent)
    })
  })

  describe('ticket fetch failure', () => {
    it('logs a warning when the ticket fetch fails with a network error', async () => {
      const fetchError = new Error('Network error')
      vi.spyOn(globalThis, 'fetch').mockRejectedValue(fetchError)

      const store = useWebSocketStore()
      await store.connect()

      expect(console.warn).toHaveBeenCalledWith(
        '[WebSocket] Ticket fetch failed',
        fetchError
      )
    })

    it('silently returns on 401 without scheduling a reconnect', async () => {
      vi.spyOn(globalThis, 'fetch').mockResolvedValue(
        new Response(JSON.stringify({ error: 'Unauthorized' }), {
          status: 401,
          headers: { 'Content-Type': 'application/json' },
        })
      )

      const store = useWebSocketStore()
      await store.connect()

      // Should not log a reconnect attempt
      const infoCalls = vi.mocked(console.info).mock.calls.flat().join(' ')
      expect(infoCalls).not.toContain('Reconnect attempt')
    })
  })

  describe('scheduleReconnect', () => {
    it('logs each reconnect attempt with the scheduled delay', async () => {
      mockSuccessfulTicketFetch()
      vi.useFakeTimers()

      const store = useWebSocketStore()
      await store.connect()

      expect(lastSocket).toBeDefined()
      // Trigger close → scheduleReconnect
      lastSocket.onclose?.(new CloseEvent('close', { code: 1006, reason: '' }))

      expect(console.info).toHaveBeenCalledWith(
        expect.stringContaining('Reconnect attempt 1 scheduled in')
      )

      vi.useRealTimers()
    })
  })
})
