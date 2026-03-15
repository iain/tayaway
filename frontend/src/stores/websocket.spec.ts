import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'

vi.mock('@/api/client', () => ({
  api: {
    post: vi.fn().mockResolvedValue({ data: { ticket: 'test-ticket' } }),
  },
}))

vi.mock('./auth', () => ({
  useAuthStore: vi.fn(() => ({ isAuthenticated: true, $reset: vi.fn() })),
}))

vi.mock('./workspace', () => ({
  useWorkspaceStore: vi.fn(() => ({
    currentWorkspaceId: 'ws-1',
    initialize: vi.fn(),
  })),
}))

vi.mock('./commandQueue', () => ({
  useCommandQueueStore: vi.fn(() => ({ processQueue: vi.fn() })),
}))

vi.mock('./notifications', () => ({
  useNotificationsStore: vi.fn(() => ({ showUpdate: vi.fn() })),
}))

vi.mock('@/router', () => ({
  default: { push: vi.fn() },
}))

type MockSocket = {
  onopen: ((event: Event) => void) | null
  onmessage: ((event: MessageEvent) => void) | null
  onclose: ((event: CloseEvent) => void) | null
  onerror: ((event: Event) => void) | null
  send: ReturnType<typeof vi.fn>
  close: ReturnType<typeof vi.fn>
  readyState: number
}

let lastSocket: MockSocket

function installWebSocketMock() {
  // Must use a real constructor function — vi.fn().mockImplementation does not
  // work correctly as a `new` target in jsdom.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const MockWebSocket = function (this: any) {
    this.onopen = null
    this.onmessage = null
    this.onclose = null
    this.onerror = null
    this.send = vi.fn()
    this.close = vi.fn()
    this.readyState = 1 // OPEN
    lastSocket = this as MockSocket
  } as unknown as typeof WebSocket
  ;(MockWebSocket as unknown as { OPEN: number }).OPEN = 1

  Object.defineProperty(window, 'WebSocket', {
    value: MockWebSocket,
    writable: true,
    configurable: true,
  })
}

describe('useWebSocketStore — connection logging', () => {
  beforeEach(() => {
    installWebSocketMock()
    setActivePinia(createPinia())
    vi.spyOn(console, 'info').mockImplementation(() => {})
    vi.spyOn(console, 'warn').mockImplementation(() => {})
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.useRealTimers()
    vi.restoreAllMocks()
    vi.resetModules()
  })

  it('logs info on open', async () => {
    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()
    await store.connect()

    lastSocket.onopen!(new Event('open'))

    expect(console.info).toHaveBeenCalledWith('[WebSocket] Connected')
  })

  it('logs warn on error', async () => {
    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()
    await store.connect()

    const errorEvent = new Event('error')
    lastSocket.onerror!(errorEvent)

    expect(console.warn).toHaveBeenCalledWith('[WebSocket] Error', errorEvent)
  })

  it('logs warn on close with code and reason', async () => {
    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()
    await store.connect()

    const closeEvent = new CloseEvent('close', { code: 1006, reason: 'Network error' })
    lastSocket.onclose!(closeEvent)

    expect(console.warn).toHaveBeenCalledWith(
      expect.stringContaining('code: 1006')
    )
    expect(console.warn).toHaveBeenCalledWith(
      expect.stringContaining('reason: Network error')
    )
  })

  it('shows "(none)" when close reason is empty', async () => {
    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()
    await store.connect()

    const closeEvent = new CloseEvent('close', { code: 1001 })
    lastSocket.onclose!(closeEvent)

    expect(console.warn).toHaveBeenCalledWith(
      expect.stringContaining('reason: (none)')
    )
  })

  it('includes reconnect attempt count in close log', async () => {
    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()
    await store.connect()

    const closeEvent = new CloseEvent('close', { code: 1001 })
    lastSocket.onclose!(closeEvent)

    expect(console.warn).toHaveBeenCalledWith(
      expect.stringContaining('reconnect attempt: 1')
    )
  })
})
