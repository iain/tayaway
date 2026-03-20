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

    const versionBefore = pool.version
    const voteVersionBefore = pool.typeVersions.get('vote')!

    sendDeleteBroadcast('event', 'evt-1')

    // All objects removed
    expect(pool.get('event', 'evt-1')).toBeUndefined()
    expect(pool.get('datePoll', 'poll-1')).toBeUndefined()
    expect(pool.get('dateRange', 'dr-1')).toBeUndefined()
    expect(pool.get('vote', 'vote-1')).toBeUndefined()
    expect(pool.get('vote', 'vote-2')).toBeUndefined()
    expect(pool.get('vote', 'vote-3')).toBeUndefined()

    // Version bumped exactly once (one bumpVersion call for all types together)
    expect(pool.version).toBe(versionBefore + 1)
    // vote type version bumped only once despite 3 votes being deleted
    expect(pool.typeVersions.get('vote')).toBe(voteVersionBefore + 1)
  })
})
