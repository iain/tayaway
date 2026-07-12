import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useCommandQueueStore, CommandQueuedError } from './commandQueue'
import { useObjectPoolStore } from './objectPool'
import { Scope } from '@/api/scope'
import { makeEvent } from '@/test/factories'
import type { ApiResponse } from '@/api/client'

// Mock commandDb
vi.mock('@/api/commandDb', () => {
  let commandStore: Map<string, unknown> = new Map()
  let nextId = 0

  return {
    addCommand: vi.fn(async () => {
      const id = `cmd-${nextId++}`
      commandStore.set(id, {})
      return id
    }),
    removeCommand: vi.fn(async (id: string) => {
      commandStore.delete(id)
    }),
    getPendingCommands: vi.fn(async () => []),
    count: vi.fn(async () => 0),
    clearAll: vi.fn(async () => {
      commandStore.clear()
    }),
    // Test helper to reset state between tests
    _reset: () => {
      commandStore = new Map()
      nextId = 0
    },
  }
})

// Mock coalesceCommands to pass through by default
vi.mock('@/api/coalesceCommands', () => ({
  coalesceCommands: vi.fn((commands) =>
    commands.map(
      (cmd: { id: string; method: string; path: string; body?: unknown }) => ({
        method: cmd.method,
        path: cmd.path,
        body: cmd.body,
        originalIds: [cmd.id],
      })
    )
  ),
}))

// Mock api client — commandQueue uses rawApi (the pure client) directly
// and calls processPoolResponse itself on success. The mock below satisfies
// both import paths.
vi.mock('@/api/client', () => ({
  rawApi: {
    post: vi.fn(),
    put: vi.fn(),
    patch: vi.fn(),
    delete: vi.fn(),
  },
}))

// Mock processPoolResponse so commandQueue's pool-hydration call after a
// successful mutation replay doesn't need a real object pool store.
vi.mock('@/api/processPoolResponse', () => ({
  processPoolResponse: vi.fn(),
}))

// Mock notifications store — hoisted and shared so tests can assert on
// showError calls across the dynamic import in processQueue
const notificationMocks = vi.hoisted(() => ({
  showError: vi.fn(),
}))

vi.mock('./notifications', () => ({
  useNotificationsStore: () => notificationMocks,
}))

// Mock other stores used in auth error handling and the isOnline signal.
// `state` is hoisted and mutable so tests can simulate a healthy socket.
const websocketMocks = vi.hoisted(() => ({
  state: 'disconnected',
}))

vi.mock('./websocket', () => ({
  useWebSocketStore: () => ({
    get state() {
      return websocketMocks.state
    },
    disconnect: vi.fn(),
  }),
}))

vi.mock('./auth', () => ({
  useAuthStore: () => ({
    $reset: vi.fn(),
  }),
}))

vi.mock('@/router', () => ({
  default: {
    push: vi.fn(),
  },
}))

import { rawApi } from '@/api/client'
import {
  addCommand,
  removeCommand,
  getPendingCommands,
  count as dbCount,
  clearAll,
} from '@/api/commandDb'

const mockedApi = rawApi as unknown as {
  post: ReturnType<typeof vi.fn>
  put: ReturnType<typeof vi.fn>
  patch: ReturnType<typeof vi.fn>
  delete: ReturnType<typeof vi.fn>
}

function okResponse<T>(data: T): ApiResponse<T> {
  return { data, status: 200 }
}

describe('commandQueue store', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.clearAllMocks()
    websocketMocks.state = 'disconnected'
  })

  describe('enqueue', () => {
    it('executes the request immediately and returns the response', async () => {
      const store = useCommandQueueStore()
      mockedApi.post.mockResolvedValueOnce(okResponse({ id: 'new-1' }))

      const result = await store.enqueue('POST', '/api/events', {
        name: 'Test',
      })

      expect(result).toEqual({ data: { id: 'new-1' }, status: 200 })
      expect(mockedApi.post).toHaveBeenCalledWith(
        '/api/events',
        { name: 'Test' },
        { idempotencyKey: expect.any(String) }
      )
    })

    it('persists the rollback linkage atomically with the command row', async () => {
      const store = useCommandQueueStore()
      mockedApi.post.mockResolvedValueOnce(okResponse(null))
      const optimistic = {
        kind: 'create' as const,
        objectType: 'event' as const,
        objectId: 'evt-1',
      }

      await store.enqueue('POST', '/api/events', { name: 'X' }, optimistic)

      expect(addCommand).toHaveBeenCalledWith(
        expect.objectContaining({ optimistic })
      )
    })

    it('persists command to db before executing', async () => {
      const store = useCommandQueueStore()
      mockedApi.put.mockResolvedValueOnce(okResponse(null))

      await store.enqueue('PUT', '/api/events/1', { name: 'Updated' })

      expect(addCommand).toHaveBeenCalledWith({
        method: 'PUT',
        path: '/api/events/1',
        body: { name: 'Updated' },
        workspaceId: null,
      })
    })

    it('tags the enqueued command with the workspace it was issued in', async () => {
      localStorage.setItem('current_workspace_id', 'ws-A')
      const { useWorkspaceStore } = await import('./workspace')
      useWorkspaceStore().initialize(['ws-A'])
      const store = useCommandQueueStore()
      mockedApi.post.mockResolvedValueOnce(okResponse(null))

      await store.enqueue('POST', '/api/events', { name: 'Event' })

      expect(addCommand).toHaveBeenCalledWith(
        expect.objectContaining({ workspaceId: 'ws-A' })
      )
      localStorage.removeItem('current_workspace_id')
    })

    it('removes command from db on success', async () => {
      const store = useCommandQueueStore()
      mockedApi.post.mockResolvedValueOnce(okResponse(null))

      await store.enqueue('POST', '/api/events', {})

      expect(removeCommand).toHaveBeenCalled()
      expect(store.pendingCount).toBe(0)
    })

    it('increments then decrements pendingCount on success', async () => {
      const store = useCommandQueueStore()
      let countDuringCall: number | undefined

      mockedApi.post.mockImplementationOnce(async () => {
        countDuringCall = store.pendingCount
        return okResponse(null)
      })

      await store.enqueue('POST', '/api/events', {})

      expect(countDuringCall).toBe(1)
      expect(store.pendingCount).toBe(0)
    })

    it('throws CommandQueuedError on network failure and keeps command in db', async () => {
      const store = useCommandQueueStore()
      const networkError = new TypeError('Failed to fetch')
      Object.defineProperty(navigator, 'onLine', {
        value: false,
        configurable: true,
      })

      mockedApi.post.mockRejectedValueOnce(networkError)

      await expect(store.enqueue('POST', '/api/events', {})).rejects.toThrow(
        CommandQueuedError
      )

      // Command stays in db (removeCommand not called after addCommand)
      expect(removeCommand).not.toHaveBeenCalled()
      expect(store.pendingCount).toBe(1)

      Object.defineProperty(navigator, 'onLine', {
        value: true,
        configurable: true,
      })
    })

    it('treats Safari "Load failed" TypeError as a network error', async () => {
      const store = useCommandQueueStore()
      const safariError = new TypeError('Load failed')
      Object.defineProperty(navigator, 'onLine', {
        value: true,
        configurable: true,
      })

      mockedApi.post.mockRejectedValueOnce(safariError)

      await expect(store.enqueue('POST', '/api/events', {})).rejects.toThrow(
        CommandQueuedError
      )

      expect(removeCommand).not.toHaveBeenCalled()
      expect(store.pendingCount).toBe(1)
    })

    // AbortSignal.timeout rejects fetch with a DOMException, not a
    // TypeError. The request may have reached the server, so the command
    // must stay queued — replays carry an Idempotency-Key, so retrying is
    // safe either way. Dropping it here silently loses the change.
    it('keeps command queued and throws CommandQueuedError on a fetch timeout', async () => {
      const store = useCommandQueueStore()
      const timeoutError = new DOMException('signal timed out', 'TimeoutError')
      mockedApi.post.mockRejectedValueOnce(timeoutError)

      await expect(store.enqueue('POST', '/api/events', {})).rejects.toThrow(
        CommandQueuedError
      )

      expect(removeCommand).not.toHaveBeenCalled()
      expect(store.pendingCount).toBe(1)
    })

    // Gateway errors are what a deploy window looks like from the client;
    // the mutation will succeed once the backend is back.
    it('keeps command queued and throws CommandQueuedError on a 503', async () => {
      const store = useCommandQueueStore()
      mockedApi.post.mockRejectedValueOnce({
        status: 503,
        message: 'Service Unavailable',
      })

      await expect(store.enqueue('POST', '/api/events', {})).rejects.toThrow(
        CommandQueuedError
      )

      expect(removeCommand).not.toHaveBeenCalled()
      expect(store.pendingCount).toBe(1)
    })

    it('removes command from db and rethrows on server error', async () => {
      const store = useCommandQueueStore()
      const serverError = { status: 422, message: 'Validation failed' }
      mockedApi.post.mockRejectedValueOnce(serverError)

      await expect(store.enqueue('POST', '/api/events', {})).rejects.toEqual(
        serverError
      )

      expect(removeCommand).toHaveBeenCalled()
      expect(store.pendingCount).toBe(0)
    })

    it('keeps command in db and throws CommandQueuedError on 401', async () => {
      const store = useCommandQueueStore()
      mockedApi.post.mockRejectedValueOnce({ status: 401 })

      await expect(
        store.enqueue('POST', '/api/events', { name: 'Test' })
      ).rejects.toThrow(CommandQueuedError)

      // Command stays in db — preserved for replay after re-auth
      expect(removeCommand).not.toHaveBeenCalled()
      expect(store.pendingCount).toBe(1)
    })

    it('dispatches to the correct HTTP method', async () => {
      const store = useCommandQueueStore()

      mockedApi.delete.mockResolvedValueOnce(okResponse(null))
      await store.enqueue('DELETE', '/api/events/1')
      expect(mockedApi.delete).toHaveBeenCalledWith('/api/events/1', {
        idempotencyKey: expect.any(String),
      })

      mockedApi.patch.mockResolvedValueOnce(okResponse(null))
      await store.enqueue('PATCH', '/api/events/1', { name: 'x' })
      expect(mockedApi.patch).toHaveBeenCalledWith(
        '/api/events/1',
        { name: 'x' },
        { idempotencyKey: expect.any(String) }
      )
    })
  })

  describe('processQueue', () => {
    it('fetches pending commands from db and executes them', async () => {
      const store = useCommandQueueStore()
      store.pendingCount = 2

      const commands = [
        {
          id: 'cmd-a',
          method: 'POST' as const,
          path: '/api/events',
          body: { name: 'A' },
          createdAt: 1,
        },
        {
          id: 'cmd-b',
          method: 'PUT' as const,
          path: '/api/events/1',
          body: { name: 'B' },
          createdAt: 2,
        },
      ]
      vi.mocked(getPendingCommands).mockResolvedValueOnce(commands)
      mockedApi.post.mockResolvedValueOnce(okResponse(null))
      mockedApi.put.mockResolvedValueOnce(okResponse(null))

      await store.processQueue()

      expect(mockedApi.post).toHaveBeenCalledWith(
        '/api/events',
        { name: 'A' },
        { idempotencyKey: expect.any(String) }
      )
      expect(mockedApi.put).toHaveBeenCalledWith(
        '/api/events/1',
        { name: 'B' },
        { idempotencyKey: expect.any(String) }
      )
      expect(store.pendingCount).toBe(0)
    })

    it('stops processing on network error and keeps remaining commands', async () => {
      const store = useCommandQueueStore()
      store.pendingCount = 2

      const commands = [
        {
          id: 'cmd-a',
          method: 'POST' as const,
          path: '/api/events',
          body: {},
          createdAt: 1,
        },
        {
          id: 'cmd-b',
          method: 'PUT' as const,
          path: '/api/events/1',
          body: {},
          createdAt: 2,
        },
      ]
      vi.mocked(getPendingCommands).mockResolvedValueOnce(commands)

      const networkError = new TypeError('Failed to fetch')
      Object.defineProperty(navigator, 'onLine', {
        value: false,
        configurable: true,
      })
      mockedApi.post.mockRejectedValueOnce(networkError)
      // processQueue always resyncs count from IndexedDB at the end
      vi.mocked(dbCount).mockResolvedValueOnce(2)

      await store.processQueue()

      // Second command was never attempted
      expect(mockedApi.put).not.toHaveBeenCalled()
      // pendingCount stays at 2 (neither removed)
      expect(store.pendingCount).toBe(2)

      Object.defineProperty(navigator, 'onLine', {
        value: true,
        configurable: true,
      })
    })

    it('stops processing on Safari "Load failed" TypeError and keeps commands', async () => {
      const store = useCommandQueueStore()
      store.pendingCount = 1

      const commands = [
        {
          id: 'cmd-a',
          method: 'POST' as const,
          path: '/api/events',
          body: {},
          createdAt: 1,
        },
      ]
      vi.mocked(getPendingCommands).mockResolvedValueOnce(commands)
      // Command is kept in DB, so resync at end of processQueue should see it
      vi.mocked(dbCount).mockResolvedValueOnce(1)

      const safariError = new TypeError('Load failed')
      Object.defineProperty(navigator, 'onLine', {
        value: true,
        configurable: true,
      })
      mockedApi.post.mockRejectedValueOnce(safariError)

      await store.processQueue()

      expect(removeCommand).not.toHaveBeenCalled()
      expect(store.pendingCount).toBe(1)
    })

    it('stops processing on a fetch timeout and keeps commands', async () => {
      const store = useCommandQueueStore()
      store.pendingCount = 1

      const commands = [
        {
          id: 'cmd-a',
          method: 'POST' as const,
          path: '/api/events',
          body: {},
          createdAt: 1,
        },
      ]
      vi.mocked(getPendingCommands).mockResolvedValueOnce(commands)
      vi.mocked(dbCount).mockResolvedValueOnce(1)

      mockedApi.post.mockRejectedValueOnce(
        new DOMException('signal timed out', 'TimeoutError')
      )

      await store.processQueue()

      expect(removeCommand).not.toHaveBeenCalled()
      expect(store.pendingCount).toBe(1)
    })

    it('removes failed server-error commands and continues with next', async () => {
      const store = useCommandQueueStore()
      store.pendingCount = 2

      const commands = [
        {
          id: 'cmd-a',
          method: 'POST' as const,
          path: '/api/events',
          body: {},
          createdAt: 1,
        },
        {
          id: 'cmd-b',
          method: 'PUT' as const,
          path: '/api/events/1',
          body: {},
          createdAt: 2,
        },
      ]
      vi.mocked(getPendingCommands).mockResolvedValueOnce(commands)

      mockedApi.post.mockRejectedValueOnce(new Error('Server error'))
      mockedApi.put.mockResolvedValueOnce(okResponse(null))
      vi.mocked(dbCount).mockResolvedValueOnce(0)

      await store.processQueue()

      // Both commands processed and removed
      expect(mockedApi.put).toHaveBeenCalled()
      expect(store.pendingCount).toBe(0)
    })

    it('does not run concurrently — sets retryRequested instead', async () => {
      const store = useCommandQueueStore()

      let resolveFirst: () => void
      const firstBlocks = new Promise<void>((r) => {
        resolveFirst = r
      })

      vi.mocked(getPendingCommands)
        .mockImplementationOnce(async () => {
          await firstBlocks
          return []
        })
        .mockResolvedValueOnce([])

      const first = store.processQueue()
      // While first is running, calling processQueue again should not start a second run
      const second = store.processQueue()

      expect(store.isProcessing).toBe(true)

      resolveFirst!()
      await first
      await second

      // getPendingCommands called twice: once for original, once for retry
      expect(getPendingCommands).toHaveBeenCalledTimes(2)
    })

    it('resets isProcessing when done', async () => {
      const store = useCommandQueueStore()
      vi.mocked(getPendingCommands).mockResolvedValueOnce([])

      await store.processQueue()

      expect(store.isProcessing).toBe(false)
    })

    it('yields to the event loop between command executions', async () => {
      vi.useFakeTimers()
      const store = useCommandQueueStore()
      store.pendingCount = 2

      const commands = [
        {
          id: 'cmd-a',
          method: 'POST' as const,
          path: '/api/events',
          body: {},
          createdAt: 1,
        },
        {
          id: 'cmd-b',
          method: 'PUT' as const,
          path: '/api/events/1',
          body: {},
          createdAt: 2,
        },
      ]
      vi.mocked(getPendingCommands).mockResolvedValueOnce(commands)
      mockedApi.post.mockResolvedValueOnce(okResponse(null))
      mockedApi.put.mockResolvedValueOnce(okResponse(null))

      const setTimeoutSpy = vi.spyOn(globalThis, 'setTimeout')

      const processing = store.processQueue()
      await vi.runAllTimersAsync()
      await processing

      // setTimeout(r, 0) should be called once per command as the event-loop yield
      const yieldCalls = setTimeoutSpy.mock.calls.filter(
        ([, delay]) => delay === 0
      )
      expect(yieldCalls.length).toBeGreaterThanOrEqual(2)

      vi.useRealTimers()
    })

    it('handles auth errors by stopping and keeping commands', async () => {
      const store = useCommandQueueStore()
      store.pendingCount = 1

      const commands = [
        {
          id: 'cmd-a',
          method: 'POST' as const,
          path: '/api/events',
          body: {},
          createdAt: 1,
        },
      ]
      vi.mocked(getPendingCommands).mockResolvedValueOnce(commands)
      mockedApi.post.mockRejectedValueOnce({ status: 401 })
      // processQueue always resyncs count from IndexedDB at the end
      vi.mocked(dbCount).mockResolvedValueOnce(1)

      await store.processQueue()

      // Command not removed from db — kept for retry after re-auth
      expect(store.pendingCount).toBe(1)
    })
  })

  // A permanent server rejection during replay must undo the optimistic
  // state the command left in the pool — otherwise the UI keeps showing a
  // change the server never accepted (temp objects even survive full syncs).
  describe('optimistic rollback on permanent replay failure', () => {
    it('removes the temp object of a failed create and names it in the toast', async () => {
      const store = useCommandQueueStore()
      const pool = useObjectPoolStore()
      pool.set(makeEvent({ id: 'evt-1' }), {
        scope: Scope.workspace('ws-1'),
        isTemp: true,
      })
      vi.mocked(getPendingCommands).mockResolvedValueOnce([
        {
          id: 'cmd-a',
          method: 'POST' as const,
          path: '/api/events',
          body: {},
          createdAt: 1,
          optimistic: {
            kind: 'create' as const,
            objectType: 'event' as const,
            objectId: 'evt-1',
          },
        },
      ])
      mockedApi.post.mockRejectedValueOnce({ status: 422, message: 'nope' })

      await store.processQueue()

      expect(pool.get('event', 'evt-1')).toBeUndefined()
      expect(removeCommand).toHaveBeenCalledWith('cmd-a')
      expect(notificationMocks.showError).toHaveBeenCalledExactlyOnceWith(
        expect.stringMatching(/event.*undone/)
      )
    })

    it('removes the pending overlay of a failed update', async () => {
      const store = useCommandQueueStore()
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent({ name: 'Original' })], {
        scope: Scope.workspace('ws-1'),
      })
      const pendingId = pool.addPending('event', 'evt-1', { name: 'Pending' })
      vi.mocked(getPendingCommands).mockResolvedValueOnce([
        {
          id: 'cmd-a',
          method: 'PUT' as const,
          path: '/api/events/evt-1',
          body: { name: 'Pending' },
          createdAt: 1,
          optimistic: {
            kind: 'update' as const,
            objectType: 'event' as const,
            objectId: 'evt-1',
            pendingId,
          },
        },
      ])
      mockedApi.put.mockRejectedValueOnce({ status: 422, message: 'nope' })

      await store.processQueue()

      expect(pool.hasPending('event', 'evt-1')).toBe(false)
      expect(pool.get('event', 'evt-1')?.name).toBe('Original')
    })

    it('restores the removed objects of a failed destroy', async () => {
      const store = useCommandQueueStore()
      const pool = useObjectPoolStore()
      vi.mocked(getPendingCommands).mockResolvedValueOnce([
        {
          id: 'cmd-a',
          method: 'DELETE' as const,
          path: '/api/events/evt-1',
          createdAt: 1,
          optimistic: {
            kind: 'destroy' as const,
            removed: [
              {
                object: makeEvent({ name: 'Deleted offline' }),
                scopes: [Scope.workspace('ws-1')],
              },
            ],
          },
        },
      ])
      mockedApi.delete.mockRejectedValueOnce({ status: 422, message: 'nope' })

      await store.processQueue()

      expect(pool.get('event', 'evt-1')?.name).toBe('Deleted offline')
    })

    it('shows one combined toast, without claiming unlinked changes were undone', async () => {
      const store = useCommandQueueStore()
      vi.mocked(getPendingCommands).mockResolvedValueOnce([
        {
          id: 'cmd-a',
          method: 'POST' as const,
          path: '/api/events',
          body: {},
          createdAt: 1,
        },
        {
          id: 'cmd-b',
          method: 'POST' as const,
          path: '/api/task-lists',
          body: {},
          createdAt: 2,
        },
      ])
      mockedApi.post.mockRejectedValue({ status: 422, message: 'nope' })

      await store.processQueue()

      // Neither command carried a rollback linkage — nothing was undone,
      // so the toast must not say so.
      expect(notificationMocks.showError).toHaveBeenCalledExactlyOnceWith(
        "2 offline changes couldn't be saved."
      )
    })

    it('counts each rolled-back change when a coalesced command fails', async () => {
      const store = useCommandQueueStore()
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent({ name: 'Original' })], {
        scope: Scope.workspace('ws-1'),
      })
      const p1 = pool.addPending('event', 'evt-1', { name: 'Edit one' })
      const p2 = pool.addPending('event', 'evt-1', { name: 'Edit two' })
      const commands = [
        {
          id: 'cmd-a',
          method: 'PUT' as const,
          path: '/api/events/evt-1',
          body: { name: 'Edit one' },
          createdAt: 1,
          optimistic: {
            kind: 'update' as const,
            objectType: 'event' as const,
            objectId: 'evt-1',
            pendingId: p1,
          },
        },
        {
          id: 'cmd-b',
          method: 'PUT' as const,
          path: '/api/events/evt-1',
          body: { name: 'Edit two' },
          createdAt: 2,
          optimistic: {
            kind: 'update' as const,
            objectType: 'event' as const,
            objectId: 'evt-1',
            pendingId: p2,
          },
        },
      ]
      vi.mocked(getPendingCommands).mockResolvedValueOnce(commands)
      // Both edits coalesce into one PUT
      const { coalesceCommands } = await import('@/api/coalesceCommands')
      vi.mocked(coalesceCommands).mockReturnValueOnce([
        {
          method: 'PUT',
          path: '/api/events/evt-1',
          body: { name: 'Edit two' },
          originalIds: ['cmd-a', 'cmd-b'],
        },
      ])
      mockedApi.put.mockRejectedValueOnce({ status: 422, message: 'nope' })

      await store.processQueue()

      expect(pool.hasPending('event', 'evt-1')).toBe(false)
      expect(notificationMocks.showError).toHaveBeenCalledExactlyOnceWith(
        "2 offline changes couldn't be saved and were undone."
      )
    })
  })

  // A 404 on DELETE means the object is already gone server-side (deleted
  // by another device/user, or a local-only zombie). That's the outcome the
  // delete wanted — treating it as failure restores/rolls back the removal
  // and resurrects objects the user can then never get rid of.
  describe('deleting an already-deleted object', () => {
    it('treats a 404 on a direct DELETE as success', async () => {
      const store = useCommandQueueStore()
      mockedApi.delete.mockRejectedValueOnce({
        status: 404,
        message: 'Task item not found',
      })

      await expect(
        store.enqueue('DELETE', '/api/task-items/x')
      ).resolves.toMatchObject({ status: 404 })

      expect(removeCommand).toHaveBeenCalled()
      expect(store.pendingCount).toBe(0)
    })

    it('treats a 404 on a DELETE replay as success — no rollback, no toast', async () => {
      const store = useCommandQueueStore()
      const pool = useObjectPoolStore()
      vi.mocked(getPendingCommands).mockResolvedValueOnce([
        {
          id: 'cmd-a',
          method: 'DELETE' as const,
          path: '/api/task-items/x',
          createdAt: 1,
          optimistic: {
            kind: 'destroy' as const,
            removed: [
              {
                object: makeEvent({ name: 'Already gone' }),
                scopes: [Scope.workspace('ws-1')],
              },
            ],
          },
        },
      ])
      mockedApi.delete.mockRejectedValueOnce({
        status: 404,
        message: 'Task item not found',
      })

      await store.processQueue()

      expect(pool.get('event', 'evt-1')).toBeUndefined()
      expect(removeCommand).toHaveBeenCalledWith('cmd-a')
      expect(notificationMocks.showError).not.toHaveBeenCalled()
    })
  })

  describe('in-flight direct requests', () => {
    // The command row is written before the direct request goes out, so a
    // concurrently-triggered drain could replay it — a duplicate request
    // whose double success corrupts pendingCount.
    it('does not replay a command whose direct request is still in flight', async () => {
      const store = useCommandQueueStore()

      let resolveDirect!: (v: ApiResponse<unknown>) => void
      mockedApi.post.mockReturnValueOnce(
        new Promise((r) => {
          resolveDirect = r
        })
      )
      const directRequest = store.enqueue('POST', '/api/events', {})
      const commandId = (await vi.mocked(addCommand).mock.results[0]!
        .value) as string

      // A drain fires while the direct request is in flight and sees its row
      vi.mocked(getPendingCommands).mockResolvedValueOnce([
        {
          id: commandId,
          method: 'POST' as const,
          path: '/api/events',
          body: {},
          createdAt: 1,
        },
      ])
      // The end-of-drain resync still counts the in-flight row
      vi.mocked(dbCount).mockResolvedValueOnce(1)
      await store.processQueue()

      // Only the direct request hit the API — no duplicate replay
      expect(mockedApi.post).toHaveBeenCalledTimes(1)

      resolveDirect(okResponse(null))
      await directRequest
      expect(store.pendingCount).toBe(0)
    })
  })

  // A fetch blip too short to drop the WebSocket queues a command that no
  // reconnect will ever replay — the queue must retry on its own while the
  // socket stays healthy.
  describe('retry while the socket stays up', () => {
    afterEach(() => {
      vi.useRealTimers()
    })

    it('schedules a retry when a command is queued while online, and replays it', async () => {
      vi.useFakeTimers()
      websocketMocks.state = 'authenticated'
      const store = useCommandQueueStore()

      mockedApi.post.mockRejectedValueOnce(new TypeError('Failed to fetch'))
      await expect(store.enqueue('POST', '/api/events', {})).rejects.toThrow(
        CommandQueuedError
      )
      expect(store.retryScheduled).toBe(true)

      // The retry replays the stored command successfully
      vi.mocked(getPendingCommands).mockResolvedValueOnce([
        {
          id: 'cmd-0',
          method: 'POST' as const,
          path: '/api/events',
          body: {},
          createdAt: 1,
        },
      ])
      mockedApi.post.mockResolvedValueOnce(okResponse(null))
      await vi.runAllTimersAsync()

      expect(removeCommand).toHaveBeenCalledWith('cmd-0')
      expect(store.retryScheduled).toBe(false)
    })

    it('keeps retrying while replays keep failing', async () => {
      vi.useFakeTimers()
      websocketMocks.state = 'authenticated'
      const store = useCommandQueueStore()

      vi.mocked(getPendingCommands).mockResolvedValue([
        {
          id: 'cmd-0',
          method: 'POST' as const,
          path: '/api/events',
          body: {},
          createdAt: 1,
        },
      ])
      vi.mocked(dbCount).mockResolvedValue(1)
      mockedApi.post.mockRejectedValue(new TypeError('Failed to fetch'))

      await expect(store.enqueue('POST', '/api/events', {})).rejects.toThrow(
        CommandQueuedError
      )
      await vi.advanceTimersByTimeAsync(120_000)

      // Initial attempt plus several retries, and another retry still armed
      expect(mockedApi.post.mock.calls.length).toBeGreaterThanOrEqual(3)
      expect(store.retryScheduled).toBe(true)
    })

    it('does not schedule a retry while the socket is down', async () => {
      vi.useFakeTimers()
      const store = useCommandQueueStore()

      mockedApi.post.mockRejectedValueOnce(new TypeError('Failed to fetch'))
      await expect(store.enqueue('POST', '/api/events', {})).rejects.toThrow(
        CommandQueuedError
      )

      // WS reconnect already triggers processQueue; no timer needed
      expect(store.retryScheduled).toBe(false)
      expect(vi.getTimerCount()).toBe(0)
    })

    it('does not schedule a retry after an auth error', async () => {
      vi.useFakeTimers()
      websocketMocks.state = 'authenticated'
      const store = useCommandQueueStore()

      mockedApi.post.mockRejectedValueOnce({ status: 401 })
      await expect(store.enqueue('POST', '/api/events', {})).rejects.toThrow(
        CommandQueuedError
      )

      expect(store.retryScheduled).toBe(false)
      expect(vi.getTimerCount()).toBe(0)
    })
  })

  describe('initialize', () => {
    function storedCommand(id: string) {
      return {
        id,
        method: 'POST' as const,
        path: '/api/events',
        body: {},
        createdAt: 1,
      }
    }

    it('loads pending count from db', async () => {
      vi.mocked(getPendingCommands).mockResolvedValueOnce([
        storedCommand('a'),
        storedCommand('b'),
        storedCommand('c'),
      ])
      // processQueue (triggered by initialize) resyncs count at the end
      vi.mocked(dbCount).mockResolvedValueOnce(3)

      const store = useCommandQueueStore()
      await store.initialize()
      // initialize fires processQueue un-awaited — settle it inside this
      // test so its mock consumption can't leak into the next one
      await vi.waitFor(() => expect(store.isProcessing).toBe(false))

      expect(store.pendingCount).toBe(3)
    })

    it('triggers processQueue when there are pending commands', async () => {
      vi.mocked(getPendingCommands).mockResolvedValueOnce([storedCommand('a')])

      const store = useCommandQueueStore()
      await store.initialize()
      await vi.waitFor(() => expect(store.isProcessing).toBe(false))

      // Once from initialize itself, once from the triggered processQueue
      expect(getPendingCommands).toHaveBeenCalledTimes(2)
    })

    it('does not trigger processQueue when queue is empty', async () => {
      vi.mocked(getPendingCommands).mockResolvedValueOnce([])

      const store = useCommandQueueStore()
      await store.initialize()

      expect(getPendingCommands).toHaveBeenCalledTimes(1)
    })

    // tempObjectIds is in-memory: after a restart, the optimistic object of
    // a still-queued create hydrates from the cache unmarked, and the next
    // (reconciliation) full sync would silently drop it.
    it('re-marks queued creates as temp so full syncs preserve them', async () => {
      vi.mocked(getPendingCommands).mockResolvedValueOnce([
        {
          ...storedCommand('a'),
          optimistic: {
            kind: 'create' as const,
            objectType: 'event' as const,
            objectId: 'evt-1',
          },
        },
      ])
      const pool = useObjectPoolStore()
      const markTemp = vi.spyOn(pool, 'markTemp')

      const store = useCommandQueueStore()
      await store.initialize()
      await vi.waitFor(() => expect(store.isProcessing).toBe(false))

      expect(markTemp).toHaveBeenCalledWith('evt-1')
    })
  })

  describe('resync on error', () => {
    it('resyncs pendingCount from db when removeCommand fails in enqueue server error path', async () => {
      const store = useCommandQueueStore()
      const serverError = { status: 422, message: 'Validation failed' }
      mockedApi.post.mockRejectedValueOnce(serverError)
      vi.mocked(removeCommand).mockRejectedValueOnce(new Error('IDB failure'))
      vi.mocked(dbCount).mockResolvedValueOnce(2)

      await expect(store.enqueue('POST', '/api/events', {})).rejects.toEqual(
        serverError
      )

      expect(dbCount).toHaveBeenCalled()
      expect(store.pendingCount).toBe(2)
    })

    it('resyncs pendingCount from db when removeCommand fails in processQueue server error path', async () => {
      const store = useCommandQueueStore()
      store.pendingCount = 1

      const commands = [
        {
          id: 'cmd-a',
          method: 'POST' as const,
          path: '/api/events',
          body: {},
          createdAt: 1,
        },
      ]
      vi.mocked(getPendingCommands).mockResolvedValueOnce(commands)
      mockedApi.post.mockRejectedValueOnce(new Error('Server error'))
      vi.mocked(removeCommand).mockRejectedValueOnce(new Error('IDB failure'))
      vi.mocked(dbCount).mockResolvedValueOnce(1)

      await store.processQueue()

      expect(dbCount).toHaveBeenCalled()
      expect(store.pendingCount).toBe(1)
    })

    it('resyncs pendingCount from db when an unexpected error escapes processQueue inner loop', async () => {
      const store = useCommandQueueStore()
      store.pendingCount = 3
      vi.mocked(getPendingCommands).mockRejectedValueOnce(
        new Error('IDB read failure')
      )
      vi.mocked(dbCount).mockResolvedValueOnce(3)

      await store.processQueue()

      expect(dbCount).toHaveBeenCalled()
      expect(store.pendingCount).toBe(3)
    })

    it('always resyncs pendingCount from db at the end of processQueue', async () => {
      const store = useCommandQueueStore()
      store.pendingCount = 1

      const commands = [
        {
          id: 'cmd-a',
          method: 'POST' as const,
          path: '/api/events',
          body: {},
          createdAt: 1,
        },
      ]
      vi.mocked(getPendingCommands).mockResolvedValueOnce(commands)
      mockedApi.post.mockResolvedValueOnce(okResponse(null))
      vi.mocked(dbCount).mockResolvedValueOnce(0)

      await store.processQueue()

      // dbCount is always called to reconcile in-memory count with IndexedDB
      expect(dbCount).toHaveBeenCalled()
      expect(store.pendingCount).toBe(0)
    })

    it('corrects drift in pendingCount if IndexedDB is ahead of in-memory count after processQueue', async () => {
      const store = useCommandQueueStore()
      // Simulate drift: in-memory says 0 but IndexedDB still has 1 item
      store.pendingCount = 0

      vi.mocked(getPendingCommands).mockResolvedValueOnce([])
      // IndexedDB reports 1 item (the in-memory count drifted low)
      vi.mocked(dbCount).mockResolvedValueOnce(1)

      await store.processQueue()

      // pendingCount is corrected upward from IndexedDB ground truth
      expect(store.pendingCount).toBe(1)
    })
  })

  describe('reset', () => {
    it('clears all commands and resets state', async () => {
      const store = useCommandQueueStore()
      store.pendingCount = 5

      await store.reset()

      expect(clearAll).toHaveBeenCalled()
      expect(store.pendingCount).toBe(0)
      expect(store.isProcessing).toBe(false)
    })
  })

  describe('$reset', () => {
    it('synchronously resets reactive state', () => {
      const store = useCommandQueueStore()
      store.pendingCount = 5
      store.isProcessing = true

      store.$reset()

      expect(store.pendingCount).toBe(0)
      expect(store.isProcessing).toBe(false)
    })
  })
})
