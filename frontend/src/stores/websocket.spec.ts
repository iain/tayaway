import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useObjectPoolStore } from './objectPool'
import {
  makeEvent,
  makeRsvp,
  makeExpense,
  makeSettlement,
  makeSettlementTransfer,
  makeChoreRoster,
  makeChore,
  makeChoreAssignment,
  makeDatePoll,
  makeDateRange,
  makeVote,
} from '@/test/factories'

// ---- WebSocket mock --------------------------------------------------------

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

// hoisted so the vi.mock factory below can reference it
const notificationsMocks = vi.hoisted(() => ({
  showUpdate: vi.fn(),
}))

const registerSWMocks = vi.hoisted(() => ({
  checkForServiceWorkerUpdate: vi.fn(),
}))

vi.mock('@/api/client', () => ({
  rawApi: {
    post: vi
      .fn()
      .mockResolvedValue({ data: { ticket: 'test-ticket' }, status: 200 }),
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
  WORKSPACE_ID_STORAGE_KEY: 'current_workspace_id',
}))

vi.mock('./commandQueue', () => ({
  useCommandQueueStore: vi.fn(() => ({ processQueue: vi.fn() })),
}))

vi.mock('./notifications', () => ({
  useNotificationsStore: vi.fn(() => ({
    showUpdate: notificationsMocks.showUpdate,
  })),
}))

vi.mock('@/api/swUpdate', () => ({
  checkForServiceWorkerUpdate: registerSWMocks.checkForServiceWorkerUpdate,
}))

vi.mock('@/router', () => ({
  default: { push: vi.fn() },
}))

// ---- Helpers ---------------------------------------------------------------

/** Send a broadcast-delete message through the WebSocket mock. */
function sendDeleteBroadcast(objectType: string, id: string): void {
  lastSocket.onmessage!({
    data: JSON.stringify({
      type: 'broadcast',
      workspaceId: 'ws-1',
      action: 'delete',
      data: { deleted: [{ objectType, id }] },
    }),
  } as MessageEvent)
}

// ---- Online event listener lifecycle tests ---------------------------------

describe('useWebSocketStore — online listener lifecycle', () => {
  let addSpy: ReturnType<typeof vi.spyOn>
  let removeSpy: ReturnType<typeof vi.spyOn>

  beforeEach(() => {
    installWebSocketMock()
    setActivePinia(createPinia())
    vi.spyOn(console, 'info').mockImplementation(() => {})
    vi.spyOn(console, 'warn').mockImplementation(() => {})
    vi.useFakeTimers()
    addSpy = vi.spyOn(window, 'addEventListener')
    removeSpy = vi.spyOn(window, 'removeEventListener')
  })

  afterEach(() => {
    vi.useRealTimers()
    vi.restoreAllMocks()
    vi.resetModules()
  })

  it('does not register the online listener before connect()', async () => {
    await import('./websocket')

    const onlineCalls = addSpy.mock.calls.filter(
      ([type]: [string]) => type === 'online'
    )
    expect(onlineCalls).toHaveLength(0)
  })

  it('registers the online listener when connect() is called', async () => {
    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()
    await store.connect()

    const onlineCalls = addSpy.mock.calls.filter(
      ([type]: [string]) => type === 'online'
    )
    expect(onlineCalls).toHaveLength(1)
    expect(typeof onlineCalls[0][1]).toBe('function')
  })

  it('removes the online listener when disconnect() is called', async () => {
    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()
    await store.connect()

    // connect() calls removeEventListener('online') once (idempotent guard)
    // before addEventListener, so clear the spy to isolate disconnect()'s call.
    removeSpy.mockClear()

    store.disconnect()

    const removedOnlineCalls = removeSpy.mock.calls.filter(
      ([type]: [string]) => type === 'online'
    )
    expect(removedOnlineCalls).toHaveLength(1)
    // The same function reference is used for add and remove
    expect(removedOnlineCalls[0][1]).toBe(
      addSpy.mock.calls.filter(([type]: [string]) => type === 'online')[0][1]
    )
  })

  it('does not trigger reconnect when online fires after disconnect()', async () => {
    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()
    await store.connect()
    store.disconnect()

    // Grab the handler that was registered and removed
    const addedHandler = addSpy.mock.calls.find(
      ([type]: [string]) => type === 'online'
    )![1] as EventListener

    // Manually invoke it as if the browser fired the event
    addedHandler(new Event('online'))

    // State should remain disconnected — no reconnect was triggered
    expect(store.state).toBe('disconnected')
  })
})

// ---- Connection logging tests ----------------------------------------------

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

    expect(console.info).toHaveBeenCalledWith(
      '[WebSocket] Connected to',
      expect.stringContaining('ticket=<redacted>')
    )
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

    const closeEvent = new CloseEvent('close', {
      code: 1006,
      reason: 'Network error',
    })
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

// ---- Cascade delete tests --------------------------------------------------

describe('websocket store — cascade delete', () => {
  beforeEach(async () => {
    installWebSocketMock()
    setActivePinia(createPinia())

    // Connect so the socket's onmessage handler is set up
    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()
    await store.connect()
  })

  afterEach(() => {
    vi.restoreAllMocks()
    vi.resetModules()
  })

  it('deleting an event cascades to rsvp', () => {
    const pool = useObjectPoolStore()
    pool.importObjects([makeEvent(), makeRsvp()], { scope: "workspace:test" })

    sendDeleteBroadcast('event', 'evt-1')

    expect(pool.get('event', 'evt-1')).toBeUndefined()
    expect(pool.get('rsvp', 'rsvp-1')).toBeUndefined()
  })

  it('deleting an event cascades to expense', () => {
    const pool = useObjectPoolStore()
    pool.importObjects([makeEvent(), makeExpense()], { scope: "workspace:test" })

    sendDeleteBroadcast('event', 'evt-1')

    expect(pool.get('event', 'evt-1')).toBeUndefined()
    expect(pool.get('expense', 'exp-1')).toBeUndefined()
  })

  it('deleting an event cascades to settlement and its transfers', () => {
    const pool = useObjectPoolStore()
    pool.importObjects([
      makeEvent(),
      makeSettlement(),
      makeSettlementTransfer(),
    ], { scope: "workspace:test" })

    sendDeleteBroadcast('event', 'evt-1')

    expect(pool.get('event', 'evt-1')).toBeUndefined()
    expect(pool.get('settlement', 'settle-1')).toBeUndefined()
    expect(pool.get('settlementTransfer', 'transfer-1')).toBeUndefined()
  })

  it('deleting an event cascades to choreRoster, chore, and choreAssignment', () => {
    const pool = useObjectPoolStore()
    pool.importObjects([
      makeEvent(),
      makeChoreRoster(),
      makeChore(),
      makeChoreAssignment(),
    ], { scope: "workspace:test" })

    sendDeleteBroadcast('event', 'evt-1')

    expect(pool.get('event', 'evt-1')).toBeUndefined()
    expect(pool.get('choreRoster', 'roster-1')).toBeUndefined()
    expect(pool.get('chore', 'chore-1')).toBeUndefined()
    expect(pool.get('choreAssignment', 'assign-1')).toBeUndefined()
  })

  it('deleting a settlement cascades to settlementTransfer', () => {
    const pool = useObjectPoolStore()
    pool.importObjects([makeSettlement(), makeSettlementTransfer()], { scope: "workspace:test" })

    sendDeleteBroadcast('settlement', 'settle-1')

    expect(pool.get('settlement', 'settle-1')).toBeUndefined()
    expect(pool.get('settlementTransfer', 'transfer-1')).toBeUndefined()
  })

  it('deleting a choreRoster cascades to chore and choreAssignment', () => {
    const pool = useObjectPoolStore()
    pool.importObjects([makeChoreRoster(), makeChore(), makeChoreAssignment()], { scope: "workspace:test" })

    sendDeleteBroadcast('choreRoster', 'roster-1')

    expect(pool.get('choreRoster', 'roster-1')).toBeUndefined()
    expect(pool.get('chore', 'chore-1')).toBeUndefined()
    expect(pool.get('choreAssignment', 'assign-1')).toBeUndefined()
  })

  it('deleting a chore cascades to choreAssignment', () => {
    const pool = useObjectPoolStore()
    pool.importObjects([makeChore(), makeChoreAssignment()], { scope: "workspace:test" })

    sendDeleteBroadcast('chore', 'chore-1')

    expect(pool.get('chore', 'chore-1')).toBeUndefined()
    expect(pool.get('choreAssignment', 'assign-1')).toBeUndefined()
  })

  it('only removes children that belong to the deleted parent', () => {
    const pool = useObjectPoolStore()
    pool.importObjects([
      makeEvent({ id: 'evt-1' }),
      makeEvent({ id: 'evt-2' }),
      makeRsvp({ id: 'rsvp-1', eventId: 'evt-1' }),
      makeRsvp({ id: 'rsvp-2', eventId: 'evt-2' }),
    ], { scope: "workspace:test" })

    sendDeleteBroadcast('event', 'evt-1')

    expect(pool.get('event', 'evt-1')).toBeUndefined()
    expect(pool.get('rsvp', 'rsvp-1')).toBeUndefined()
    expect(pool.get('event', 'evt-2')).toBeDefined()
    expect(pool.get('rsvp', 'rsvp-2')).toBeDefined()
  })

  it('handles cascade delete when there are no children', () => {
    const pool = useObjectPoolStore()
    pool.importObjects([makeEvent()], { scope: "workspace:test" })

    expect(() => sendDeleteBroadcast('event', 'evt-1')).not.toThrow()
    expect(pool.get('event', 'evt-1')).toBeUndefined()
  })

  it('increments the pool version only once per type when cascading many deletions', () => {
    const pool = useObjectPoolStore()

    // Build: 1 event → 1 datePoll → 1 dateRange → 3 votes (6 total objects)
    pool.importObjects([
      makeEvent(),
      makeDatePoll(),
      makeDateRange(),
      makeVote({ id: 'vote-1', dateRangeId: 'dr-1' }),
      makeVote({ id: 'vote-2', dateRangeId: 'dr-1' }),
      makeVote({ id: 'vote-3', dateRangeId: 'dr-1' }),
    ], { scope: "workspace:test" })

    const voteVersionBefore = pool.getVersion('vote')
    // Type not involved should not change
    const taskItemVersionBefore = pool.getVersion('taskItem')

    sendDeleteBroadcast('event', 'evt-1')

    // All objects removed
    expect(pool.get('event', 'evt-1')).toBeUndefined()
    expect(pool.get('datePoll', 'poll-1')).toBeUndefined()
    expect(pool.get('dateRange', 'dr-1')).toBeUndefined()
    expect(pool.get('vote', 'vote-1')).toBeUndefined()
    expect(pool.get('vote', 'vote-2')).toBeUndefined()
    expect(pool.get('vote', 'vote-3')).toBeUndefined()

    // vote type version bumped only once despite 3 votes being deleted
    expect(pool.getVersion('vote')).toBe(voteVersionBefore + 1)
    // Unaffected types must not be bumped
    expect(pool.getVersion('taskItem')).toBe(taskItemVersionBefore)
  })
})

// ---- state reset after ticket failure tests --------------------------------

describe('useWebSocketStore — state reset after ticket failure', () => {
  beforeEach(() => {
    installWebSocketMock()
    setActivePinia(createPinia())
    vi.spyOn(console, 'warn').mockImplementation(() => {})
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.useRealTimers()
    vi.restoreAllMocks()
    vi.resetModules()
  })

  it('resets state to disconnected when ticket fetch is aborted', async () => {
    const { rawApi } = await import('@/api/client')
    const abortError = new DOMException(
      'The operation was aborted.',
      'AbortError'
    )
    vi.mocked(rawApi.post).mockRejectedValueOnce(abortError)

    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()

    await store.connect()

    // State must be 'disconnected' so the next connect() attempt is not blocked
    expect(store.state).toBe('disconnected')
  })

  it('resets state to disconnected when ticket fetch throws a network error', async () => {
    const { rawApi } = await import('@/api/client')
    vi.mocked(rawApi.post).mockRejectedValueOnce(new Error('Network error'))

    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()

    await store.connect()

    expect(store.state).toBe('disconnected')
  })

  it('allows a subsequent connect() after ticket timeout clears state', async () => {
    const { rawApi } = await import('@/api/client')
    const abortError = new DOMException(
      'The operation was aborted.',
      'AbortError'
    )
    // First call times out, second succeeds
    vi.mocked(rawApi.post)
      .mockRejectedValueOnce(abortError)
      .mockResolvedValueOnce({ data: { ticket: 'test-ticket' }, status: 200 })

    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()

    await store.connect()
    expect(store.state).toBe('disconnected')

    // A second connect() must not be blocked by the guard — verify the ticket
    // endpoint is called again (state was 'disconnected', so connect() ran)
    vi.mocked(rawApi.post).mockClear()
    await store.connect()
    expect(vi.mocked(rawApi.post)).toHaveBeenCalledTimes(1)
  })
})

// ---- connectionFailed tests ------------------------------------------------

describe('useWebSocketStore — connectionFailed', () => {
  beforeEach(() => {
    installWebSocketMock()
    setActivePinia(createPinia())
    vi.spyOn(console, 'warn').mockImplementation(() => {})
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.useRealTimers()
    vi.restoreAllMocks()
    vi.resetModules()
  })

  it('sets connectionFailed when ticket fetch throws a network error', async () => {
    const { rawApi } = await import('@/api/client')
    vi.mocked(rawApi.post).mockRejectedValueOnce(new Error('Network error'))

    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()

    expect(store.connectionFailed).toBe(false)
    await store.connect()
    expect(store.connectionFailed).toBe(true)
  })

  it('sets connectionFailed when ticket fetch is aborted (timeout)', async () => {
    const { rawApi } = await import('@/api/client')
    const abortError = new DOMException(
      'The operation was aborted.',
      'AbortError'
    )
    vi.mocked(rawApi.post).mockRejectedValueOnce(abortError)

    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()

    expect(store.connectionFailed).toBe(false)
    await store.connect()
    expect(store.connectionFailed).toBe(true)
  })

  it('does not set connectionFailed on a 401 (session expired)', async () => {
    const { rawApi } = await import('@/api/client')
    vi.mocked(rawApi.post).mockRejectedValueOnce({
      status: 401,
      message: 'Unauthorized',
    })

    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()

    await store.connect()
    expect(store.connectionFailed).toBe(false)
  })

  it('does not set connectionFailed on a successful connection', async () => {
    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()

    await store.connect()
    expect(store.connectionFailed).toBe(false)
  })

  it('resets connectionFailed on disconnect', async () => {
    const { rawApi } = await import('@/api/client')
    vi.mocked(rawApi.post).mockRejectedValueOnce(new Error('Network error'))

    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()

    await store.connect()
    expect(store.connectionFailed).toBe(true)

    store.disconnect()
    expect(store.connectionFailed).toBe(false)
  })

  it('resets connectionFailed when a subsequent connect succeeds', async () => {
    const { rawApi } = await import('@/api/client')
    vi.mocked(rawApi.post).mockRejectedValueOnce(new Error('Network error'))

    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()

    await store.connect()
    expect(store.connectionFailed).toBe(true)

    // state is 'disconnected' after the failed attempt, so connect() can run again
    await store.connect()
    expect(store.connectionFailed).toBe(false)
  })
})

// ---- gitSha update-trigger tests -------------------------------------------

describe('useWebSocketStore — gitSha triggers SW update on version change', () => {
  beforeEach(() => {
    installWebSocketMock()
    setActivePinia(createPinia())
    vi.spyOn(console, 'info').mockImplementation(() => {})
    vi.spyOn(console, 'warn').mockImplementation(() => {})

    notificationsMocks.showUpdate.mockReset()
    registerSWMocks.checkForServiceWorkerUpdate.mockReset()
  })

  afterEach(() => {
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
    vi.resetModules()
  })

  it('triggers a service worker update check when the gitSha changes', async () => {
    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()
    await store.connect()
    lastSocket.onopen!(new Event('open'))

    // First pong — sets the initial gitSha, no update triggered yet
    lastSocket.onmessage!({
      data: JSON.stringify({ type: 'pong', gitSha: 'abc123' }),
    } as MessageEvent)
    await new Promise((resolve) => setTimeout(resolve, 0))
    expect(registerSWMocks.checkForServiceWorkerUpdate).not.toHaveBeenCalled()

    // Second pong with a different gitSha — triggers the SW update check
    lastSocket.onmessage!({
      data: JSON.stringify({ type: 'pong', gitSha: 'def456' }),
    } as MessageEvent)
    await new Promise((resolve) => setTimeout(resolve, 0))
    expect(registerSWMocks.checkForServiceWorkerUpdate).toHaveBeenCalledOnce()
  })

  it('does not trigger an update when the gitSha stays the same', async () => {
    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()
    await store.connect()
    lastSocket.onopen!(new Event('open'))

    lastSocket.onmessage!({
      data: JSON.stringify({ type: 'pong', gitSha: 'abc123' }),
    } as MessageEvent)
    await new Promise((resolve) => setTimeout(resolve, 0))

    lastSocket.onmessage!({
      data: JSON.stringify({ type: 'pong', gitSha: 'abc123' }),
    } as MessageEvent)
    await new Promise((resolve) => setTimeout(resolve, 0))

    expect(registerSWMocks.checkForServiceWorkerUpdate).not.toHaveBeenCalled()
  })

  it('does not show its own update notification from handlePong', async () => {
    // The standard onNeedRefresh flow in registerSW.ts is responsible for
    // surfacing the update notification once Workbox detects the new SW.
    // handlePong should not duplicate it.
    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()
    await store.connect()
    lastSocket.onopen!(new Event('open'))

    lastSocket.onmessage!({
      data: JSON.stringify({ type: 'pong', gitSha: 'abc123' }),
    } as MessageEvent)
    await new Promise((resolve) => setTimeout(resolve, 0))
    lastSocket.onmessage!({
      data: JSON.stringify({ type: 'pong', gitSha: 'def456' }),
    } as MessageEvent)
    await new Promise((resolve) => setTimeout(resolve, 0))

    expect(notificationsMocks.showUpdate).not.toHaveBeenCalled()
  })
})

// ---- pong timeout / dead-connection detection -----------------------------

describe('useWebSocketStore — pong timeout', () => {
  beforeEach(() => {
    installWebSocketMock()
    setActivePinia(createPinia())
    vi.spyOn(console, 'info').mockImplementation(() => {})
    vi.spyOn(console, 'warn').mockImplementation(() => {})
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.useRealTimers()
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
    vi.resetModules()
  })

  it('forces a reconnect when no pong arrives within the timeout', async () => {
    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()
    await store.connect()
    lastSocket.onopen!(new Event('open'))
    // Transition to authenticated so the ping interval is armed
    lastSocket.onmessage!({
      data: JSON.stringify({
        type: 'authenticated',
        userId: 'u1',
        workspaceIds: ['ws-1'],
      }),
    } as MessageEvent)
    await vi.advanceTimersByTimeAsync(0)

    const firstSocket = lastSocket
    const closeSpy = vi.spyOn(firstSocket, 'close')

    // Advance 30s → ping fires and arms pong timeout
    await vi.advanceTimersByTimeAsync(30_000)
    // Advance 10s more → pong timeout fires, which calls reconnect()
    // reconnect() closes the old socket and opens a new one
    await vi.advanceTimersByTimeAsync(10_000)

    expect(closeSpy).toHaveBeenCalled()
  })

  it('does not force a reconnect when a pong arrives before the timeout', async () => {
    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()
    await store.connect()
    lastSocket.onopen!(new Event('open'))
    lastSocket.onmessage!({
      data: JSON.stringify({
        type: 'authenticated',
        userId: 'u1',
        workspaceIds: ['ws-1'],
      }),
    } as MessageEvent)
    await vi.advanceTimersByTimeAsync(0)

    const firstSocket = lastSocket
    const closeSpy = vi.spyOn(firstSocket, 'close')

    // Advance 30s → ping fires and arms pong timeout
    await vi.advanceTimersByTimeAsync(30_000)
    // Server replies within the timeout window
    lastSocket.onmessage!({
      data: JSON.stringify({ type: 'pong' }),
    } as MessageEvent)
    // Advance past where the timeout would have fired
    await vi.advanceTimersByTimeAsync(15_000)

    expect(closeSpy).not.toHaveBeenCalled()
  })
})
