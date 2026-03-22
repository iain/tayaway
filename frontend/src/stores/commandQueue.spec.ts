import { describe, it, expect, beforeEach, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useCommandQueueStore, CommandQueuedError } from './commandQueue'
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

// Mock api client
vi.mock('@/api/client', () => ({
  api: {
    post: vi.fn(),
    put: vi.fn(),
    patch: vi.fn(),
    delete: vi.fn(),
  },
}))

// Mock notifications store
vi.mock('./notifications', () => ({
  useNotificationsStore: () => ({
    showError: vi.fn(),
  }),
}))

// Mock other stores used in auth error handling
vi.mock('./websocket', () => ({
  useWebSocketStore: () => ({
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

import { api } from '@/api/client'
import {
  addCommand,
  removeCommand,
  getPendingCommands,
  count as dbCount,
  clearAll,
} from '@/api/commandDb'

const mockedApi = api as unknown as {
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
  })

  describe('enqueue', () => {
    it('executes the request immediately and returns the response', async () => {
      const store = useCommandQueueStore()
      mockedApi.post.mockResolvedValueOnce(okResponse({ id: 'new-1' }))

      const result = await store.enqueue('POST', '/api/events', {
        name: 'Test',
      })

      expect(result).toEqual({ data: { id: 'new-1' }, status: 200 })
      expect(mockedApi.post).toHaveBeenCalledWith('/api/events', {
        name: 'Test',
      })
    })

    it('persists command to db before executing', async () => {
      const store = useCommandQueueStore()
      mockedApi.put.mockResolvedValueOnce(okResponse(null))

      await store.enqueue('PUT', '/api/events/1', { name: 'Updated' })

      expect(addCommand).toHaveBeenCalledWith({
        method: 'PUT',
        path: '/api/events/1',
        body: { name: 'Updated' },
      })
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
      expect(mockedApi.delete).toHaveBeenCalledWith('/api/events/1')

      mockedApi.patch.mockResolvedValueOnce(okResponse(null))
      await store.enqueue('PATCH', '/api/events/1', { name: 'x' })
      expect(mockedApi.patch).toHaveBeenCalledWith('/api/events/1', {
        name: 'x',
      })
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

      expect(mockedApi.post).toHaveBeenCalledWith('/api/events', { name: 'A' })
      expect(mockedApi.put).toHaveBeenCalledWith('/api/events/1', { name: 'B' })
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

      await store.processQueue()

      // Command not removed from db — kept for retry after re-auth
      expect(store.pendingCount).toBe(1)
    })
  })

  describe('initialize', () => {
    it('loads pending count from db', async () => {
      vi.mocked(dbCount).mockResolvedValueOnce(3)
      vi.mocked(getPendingCommands).mockResolvedValueOnce([])

      const store = useCommandQueueStore()
      await store.initialize()

      expect(store.pendingCount).toBe(3)
    })

    it('triggers processQueue when there are pending commands', async () => {
      vi.mocked(dbCount).mockResolvedValueOnce(2)
      vi.mocked(getPendingCommands).mockResolvedValueOnce([])

      const store = useCommandQueueStore()
      await store.initialize()

      // processQueue was called, which calls getPendingCommands
      expect(getPendingCommands).toHaveBeenCalled()
    })

    it('does not trigger processQueue when queue is empty', async () => {
      vi.mocked(dbCount).mockResolvedValueOnce(0)

      const store = useCommandQueueStore()
      await store.initialize()

      expect(getPendingCommands).not.toHaveBeenCalled()
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

    it('does not call dbCount on the happy path in processQueue', async () => {
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

      await store.processQueue()

      expect(dbCount).not.toHaveBeenCalled()
      expect(store.pendingCount).toBe(0)
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
