import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useObjectPoolStore } from './objectPool'
import type { ObjectTypeMap } from '@/types/pool'

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

vi.mock('@/api/client', () => ({
  api: {
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
}))

vi.mock('./commandQueue', () => ({
  useCommandQueueStore: vi.fn(() => ({ processQueue: vi.fn() })),
}))

vi.mock('./notifications', () => ({
  useNotificationsStore: vi.fn(() => ({
    showUpdate: notificationsMocks.showUpdate,
  })),
}))

vi.mock('@/router', () => ({
  default: { push: vi.fn() },
}))

// ---- Helpers ---------------------------------------------------------------

function ts(offset = 0): string {
  return new Date(Date.now() + offset).toISOString()
}

function makeEvent(
  overrides: Partial<ObjectTypeMap['event']> = {}
): ObjectTypeMap['event'] {
  return {
    id: 'evt-1',
    objectType: 'event',
    name: 'Test Event',
    description: null,
    startDate: null,
    endDate: null,
    locationName: null,
    latitude: null,
    longitude: null,
    workspaceId: 'ws-1',
    userId: 'user-1',
    datePollId: null,
    rsvpIds: [],
    createdAt: ts(),
    updatedAt: ts(),
    ...overrides,
  }
}

function makeRsvp(
  overrides: Partial<ObjectTypeMap['rsvp']> = {}
): ObjectTypeMap['rsvp'] {
  return {
    id: 'rsvp-1',
    objectType: 'rsvp',
    eventId: 'evt-1',
    userId: 'user-1',
    attending: true,
    startDate: null,
    endDate: null,
    createdAt: ts(),
    updatedAt: ts(),
    ...overrides,
  }
}

function makeExpense(
  overrides: Partial<ObjectTypeMap['expense']> = {}
): ObjectTypeMap['expense'] {
  return {
    id: 'exp-1',
    objectType: 'expense',
    eventId: 'evt-1',
    userId: 'user-1',
    settlementId: null,
    description: 'Hotel',
    amount: 100,
    startDate: '2026-03-01',
    endDate: '2026-03-03',
    participantIds: [],
    createdAt: ts(),
    updatedAt: ts(),
    ...overrides,
  }
}

function makeSettlement(
  overrides: Partial<ObjectTypeMap['settlement']> = {}
): ObjectTypeMap['settlement'] {
  return {
    id: 'settle-1',
    objectType: 'settlement',
    eventId: 'evt-1',
    userId: 'user-1',
    transferIds: [],
    createdAt: ts(),
    updatedAt: ts(),
    ...overrides,
  }
}

function makeSettlementTransfer(
  overrides: Partial<ObjectTypeMap['settlementTransfer']> = {}
): ObjectTypeMap['settlementTransfer'] {
  return {
    id: 'transfer-1',
    objectType: 'settlementTransfer',
    settlementId: 'settle-1',
    fromUserId: 'user-1',
    toUserId: 'user-2',
    amount: 50,
    paidAt: null,
    createdAt: ts(),
    updatedAt: ts(),
    ...overrides,
  }
}

function makeChoreRoster(
  overrides: Partial<ObjectTypeMap['choreRoster']> = {}
): ObjectTypeMap['choreRoster'] {
  return {
    id: 'roster-1',
    objectType: 'choreRoster',
    eventId: 'evt-1',
    userId: 'user-1',
    choreIds: [],
    createdAt: ts(),
    updatedAt: ts(),
    ...overrides,
  }
}

function makeChore(
  overrides: Partial<ObjectTypeMap['chore']> = {}
): ObjectTypeMap['chore'] {
  return {
    id: 'chore-1',
    objectType: 'chore',
    choreRosterId: 'roster-1',
    name: 'Dishes',
    peoplePerDay: 1,
    position: 1,
    assignmentIds: [],
    createdAt: ts(),
    updatedAt: ts(),
    ...overrides,
  }
}

function makeChoreAssignment(
  overrides: Partial<ObjectTypeMap['choreAssignment']> = {}
): ObjectTypeMap['choreAssignment'] {
  return {
    id: 'assign-1',
    objectType: 'choreAssignment',
    choreId: 'chore-1',
    userId: 'user-1',
    date: '2026-03-10',
    pinned: false,
    note: null,
    createdAt: ts(),
    updatedAt: ts(),
    ...overrides,
  }
}

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
    pool.importObjects([makeEvent(), makeRsvp()])

    sendDeleteBroadcast('event', 'evt-1')

    expect(pool.get('event', 'evt-1')).toBeUndefined()
    expect(pool.get('rsvp', 'rsvp-1')).toBeUndefined()
  })

  it('deleting an event cascades to expense', () => {
    const pool = useObjectPoolStore()
    pool.importObjects([makeEvent(), makeExpense()])

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
    ])

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
    ])

    sendDeleteBroadcast('event', 'evt-1')

    expect(pool.get('event', 'evt-1')).toBeUndefined()
    expect(pool.get('choreRoster', 'roster-1')).toBeUndefined()
    expect(pool.get('chore', 'chore-1')).toBeUndefined()
    expect(pool.get('choreAssignment', 'assign-1')).toBeUndefined()
  })

  it('deleting a settlement cascades to settlementTransfer', () => {
    const pool = useObjectPoolStore()
    pool.importObjects([makeSettlement(), makeSettlementTransfer()])

    sendDeleteBroadcast('settlement', 'settle-1')

    expect(pool.get('settlement', 'settle-1')).toBeUndefined()
    expect(pool.get('settlementTransfer', 'transfer-1')).toBeUndefined()
  })

  it('deleting a choreRoster cascades to chore and choreAssignment', () => {
    const pool = useObjectPoolStore()
    pool.importObjects([makeChoreRoster(), makeChore(), makeChoreAssignment()])

    sendDeleteBroadcast('choreRoster', 'roster-1')

    expect(pool.get('choreRoster', 'roster-1')).toBeUndefined()
    expect(pool.get('chore', 'chore-1')).toBeUndefined()
    expect(pool.get('choreAssignment', 'assign-1')).toBeUndefined()
  })

  it('deleting a chore cascades to choreAssignment', () => {
    const pool = useObjectPoolStore()
    pool.importObjects([makeChore(), makeChoreAssignment()])

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
    ])

    sendDeleteBroadcast('event', 'evt-1')

    expect(pool.get('event', 'evt-1')).toBeUndefined()
    expect(pool.get('rsvp', 'rsvp-1')).toBeUndefined()
    expect(pool.get('event', 'evt-2')).toBeDefined()
    expect(pool.get('rsvp', 'rsvp-2')).toBeDefined()
  })

  it('handles cascade delete when there are no children', () => {
    const pool = useObjectPoolStore()
    pool.importObjects([makeEvent()])

    expect(() => sendDeleteBroadcast('event', 'evt-1')).not.toThrow()
    expect(pool.get('event', 'evt-1')).toBeUndefined()
  })

  it('increments the pool version only once per type when cascading many deletions', () => {
    const pool = useObjectPoolStore()

    function makeDatePoll(
      overrides: Partial<ObjectTypeMap['datePoll']> = {}
    ): ObjectTypeMap['datePoll'] {
      return {
        id: 'poll-1',
        objectType: 'datePoll',
        eventId: 'evt-1',
        deadline: '2026-06-01T00:00:00.000Z',
        selectedDateRangeId: null,
        closedAt: null,
        status: 'open',
        dateRangeIds: [],
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
        ...overrides,
      }
    }

    function makeDateRange(
      overrides: Partial<ObjectTypeMap['dateRange']> = {}
    ): ObjectTypeMap['dateRange'] {
      return {
        id: 'dr-1',
        objectType: 'dateRange',
        datePollId: 'poll-1',
        startDate: '2026-06-10',
        endDate: '2026-06-12',
        voteIds: [],
        updatedAt: new Date().toISOString(),
        ...overrides,
      }
    }

    function makeVote(
      overrides: Partial<ObjectTypeMap['vote']> = {}
    ): ObjectTypeMap['vote'] {
      return {
        id: 'vote-1',
        objectType: 'vote',
        dateRangeId: 'dr-1',
        userId: 'user-1',
        response: 'yes',
        comment: null,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
        ...overrides,
      }
    }

    // Build: 1 event → 1 datePoll → 1 dateRange → 3 votes (6 total objects)
    pool.importObjects([
      makeEvent(),
      makeDatePoll(),
      makeDateRange(),
      makeVote({ id: 'vote-1', dateRangeId: 'dr-1' }),
      makeVote({ id: 'vote-2', dateRangeId: 'dr-1' }),
      makeVote({ id: 'vote-3', dateRangeId: 'dr-1' }),
    ])

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
    const { api } = await import('@/api/client')
    const abortError = new DOMException(
      'The operation was aborted.',
      'AbortError'
    )
    vi.mocked(api.post).mockRejectedValueOnce(abortError)

    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()

    await store.connect()

    // State must be 'disconnected' so the next connect() attempt is not blocked
    expect(store.state).toBe('disconnected')
  })

  it('resets state to disconnected when ticket fetch throws a network error', async () => {
    const { api } = await import('@/api/client')
    vi.mocked(api.post).mockRejectedValueOnce(new Error('Network error'))

    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()

    await store.connect()

    expect(store.state).toBe('disconnected')
  })

  it('allows a subsequent connect() after ticket timeout clears state', async () => {
    const { api } = await import('@/api/client')
    const abortError = new DOMException(
      'The operation was aborted.',
      'AbortError'
    )
    // First call times out, second succeeds
    vi.mocked(api.post)
      .mockRejectedValueOnce(abortError)
      .mockResolvedValueOnce({ data: { ticket: 'test-ticket' }, status: 200 })

    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()

    await store.connect()
    expect(store.state).toBe('disconnected')

    // A second connect() must not be blocked by the guard — verify the ticket
    // endpoint is called again (state was 'disconnected', so connect() ran)
    vi.mocked(api.post).mockClear()
    await store.connect()
    expect(vi.mocked(api.post)).toHaveBeenCalledTimes(1)
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
    const { api } = await import('@/api/client')
    vi.mocked(api.post).mockRejectedValueOnce(new Error('Network error'))

    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()

    expect(store.connectionFailed).toBe(false)
    await store.connect()
    expect(store.connectionFailed).toBe(true)
  })

  it('sets connectionFailed when ticket fetch is aborted (timeout)', async () => {
    const { api } = await import('@/api/client')
    const abortError = new DOMException(
      'The operation was aborted.',
      'AbortError'
    )
    vi.mocked(api.post).mockRejectedValueOnce(abortError)

    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()

    expect(store.connectionFailed).toBe(false)
    await store.connect()
    expect(store.connectionFailed).toBe(true)
  })

  it('does not set connectionFailed on a 401 (session expired)', async () => {
    const { api } = await import('@/api/client')
    vi.mocked(api.post).mockRejectedValueOnce({
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
    const { api } = await import('@/api/client')
    vi.mocked(api.post).mockRejectedValueOnce(new Error('Network error'))

    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()

    await store.connect()
    expect(store.connectionFailed).toBe(true)

    store.disconnect()
    expect(store.connectionFailed).toBe(false)
  })

  it('resets connectionFailed when a subsequent connect succeeds', async () => {
    const { api } = await import('@/api/client')
    vi.mocked(api.post).mockRejectedValueOnce(new Error('Network error'))

    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()

    await store.connect()
    expect(store.connectionFailed).toBe(true)

    // state is 'disconnected' after the failed attempt, so connect() can run again
    await store.connect()
    expect(store.connectionFailed).toBe(false)
  })
})

// ---- gitSha cache-clear tests ----------------------------------------------

describe('useWebSocketStore — gitSha cache-clear on version change', () => {
  let reloadMock: ReturnType<typeof vi.fn>
  let cachesDeleteMock: ReturnType<typeof vi.fn>

  beforeEach(() => {
    installWebSocketMock()
    setActivePinia(createPinia())
    vi.spyOn(console, 'info').mockImplementation(() => {})
    vi.spyOn(console, 'warn').mockImplementation(() => {})

    // jsdom's window.location is not configurable, so we replace it entirely
    reloadMock = vi.fn()
    vi.stubGlobal('location', {
      ...window.location,
      reload: reloadMock,
    })

    cachesDeleteMock = vi.fn().mockResolvedValue(true)
    vi.stubGlobal('caches', {
      keys: vi.fn().mockResolvedValue(['cache-v1', 'cache-v2']),
      delete: cachesDeleteMock,
    })

    notificationsMocks.showUpdate.mockReset()
  })

  afterEach(() => {
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
    vi.resetModules()
  })

  it('calls showUpdate when the gitSha changes between pongs', async () => {
    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()
    await store.connect()
    lastSocket.onopen!(new Event('open'))

    // First pong — sets the initial gitSha, no update shown yet
    lastSocket.onmessage!({
      data: JSON.stringify({ type: 'pong', gitSha: 'abc123' }),
    } as MessageEvent)
    await new Promise((resolve) => setTimeout(resolve, 0))
    expect(notificationsMocks.showUpdate).not.toHaveBeenCalled()

    // Second pong with a different gitSha — triggers the update notification
    lastSocket.onmessage!({
      data: JSON.stringify({ type: 'pong', gitSha: 'def456' }),
    } as MessageEvent)
    await new Promise((resolve) => setTimeout(resolve, 0))
    expect(notificationsMocks.showUpdate).toHaveBeenCalledOnce()
  })

  it('does not call showUpdate when the gitSha stays the same', async () => {
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

    expect(notificationsMocks.showUpdate).not.toHaveBeenCalled()
  })

  it('cache-clear action awaits all deletions before calling reload', async () => {
    // Capture the async action passed to showUpdate
    let capturedAction: (() => void | Promise<void>) | undefined
    notificationsMocks.showUpdate.mockImplementation(
      (action: () => void | Promise<void>) => {
        capturedAction = action
      }
    )

    const { useWebSocketStore } = await import('./websocket')
    const store = useWebSocketStore()
    await store.connect()
    lastSocket.onopen!(new Event('open'))

    // Trigger a gitSha change so showUpdate is called
    lastSocket.onmessage!({
      data: JSON.stringify({ type: 'pong', gitSha: 'abc123' }),
    } as MessageEvent)
    await new Promise((resolve) => setTimeout(resolve, 0))
    lastSocket.onmessage!({
      data: JSON.stringify({ type: 'pong', gitSha: 'def456' }),
    } as MessageEvent)
    await new Promise((resolve) => setTimeout(resolve, 0))

    expect(capturedAction).toBeDefined()

    // Invoke the captured async action and await its completion
    await capturedAction!()

    // All cache keys deleted before reload is called
    expect(cachesDeleteMock).toHaveBeenCalledWith('cache-v1')
    expect(cachesDeleteMock).toHaveBeenCalledWith('cache-v2')
    expect(cachesDeleteMock).toHaveBeenCalledTimes(2)
    expect(reloadMock).toHaveBeenCalledOnce()
  })
})
